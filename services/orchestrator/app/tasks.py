import os
import time
import asyncio
from app.db import AsyncSessionLocal
from app.models import Run, SubAgent, Checkpoint, Approval
from sqlalchemy import update
from app.metrics import RUNS_FINISHED

async def _update_run(session, run_id, **kwargs):
    await session.execute(update(Run).where(Run.id == run_id).values(**kwargs))
    await session.commit()

async def execute_run_async(run_id: str):
    async with AsyncSessionLocal() as session:
        run = await session.get(Run, run_id)
        if not run:
            print(f"Run {run_id} not found")
            return
        # update run -> running
        try:
            await _update_run(session, run_id, status='running', started_at=time.strftime('%Y-%m-%d %H:%M:%S'))
        except Exception:
            pass

        sub = await session.get(SubAgent, run.subagent_id)
        # Example behavior: if run_spec requests approval, create approval and wait
        requires_approval = False
        try:
            requires_approval = run.inputs.get('requires_approval', False)
        except Exception:
            requires_approval = False

        try:
            if requires_approval:
                print('Run requires human approval; creating approval and pausing')
                appv = Approval(run_id=run.id, status='requested')
                session.add(appv)
                await session.commit()
                # poll for approval
                waited = 0
                while waited < 3600:
                    await asyncio.sleep(5)
                    waited += 5
                    refreshed = await session.get(Approval, appv.id)
                    if refreshed.status == 'approved':
                        print('Approval granted, continuing')
                        break
                    if refreshed.status == 'rejected':
                        print('Approval rejected, aborting')
                        await _update_run(session, run_id, status='failed')
                        return
                else:
                    print('Approval timed out')
                    await _update_run(session, run_id, status='failed')
                    return

            # Simulate work or run container if docker socket available
            docker_sock = os.environ.get('DOCKER_SOCK', '/var/run/docker.sock')
            if os.path.exists(docker_sock):
                try:
                    import docker
                    client = docker.DockerClient(base_url='unix://' + docker_sock)
                    image = sub.run_spec.get('image') if sub and sub.run_spec else None
                    if not image:
                        image = 'subagent_template:latest'
                    print('Pulling and running image', image)
                    client.images.pull(image)
                    container = client.containers.run(image, detach=True, environment={'AGENT_SPEC': '{}'})
                    # save container id
                    sub.docker_container_id = container.id
                    await session.commit()
                    # wait for completion
                    for _ in range(3600):
                        container.reload()
                        if container.status in ('exited', 'dead'):
                            break
                        await asyncio.sleep(1)
                    logs = container.logs().decode('utf-8', errors='ignore')
                    outputs = {'logs': logs}
                except Exception as e:
                    print('Docker run failed, falling back to simulated run', e)
                    raise
            else:
                print('No docker socket found, running simulated task')
                await asyncio.sleep(3)
                outputs = {'result': 'simulated', 'summary': 'Task completed successfully'}

            # write outputs and checkpoint
            run.outputs = outputs
            run.status = 'finished'
            run.finished_at = time.strftime('%Y-%m-%d %H:%M:%S')
            session.add(run)
            checkpoint = Checkpoint(run_id=run.id, state={'outputs': outputs}, artifact_location='s3://minio/artifacts')
            session.add(checkpoint)
            await session.commit()
            try:
                RUNS_FINISHED.inc()
            except Exception:
                pass
            print('Run completed', run.id)
        except Exception as exc:
            # record failure and re-raise so RQ can retry according to policy
            try:
                run.outputs = {'error': str(exc)}
                run.status = 'error'
                session.add(run)
                await session.commit()
            except Exception:
                pass
            print('Run failed with exception:', exc)
            raise


def execute_run(run_id: str):
    # wrapper for RQ worker (sync entry)
    asyncio.run(execute_run_async(run_id))
