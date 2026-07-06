@@
 @router.post('/approvals/{approval_id}/act')
 async def act_approval(approval_id: UUID, payload: ApprovalAct, user=Depends(require_role('approver', 'admin'))):
     appv = await crud.act_on_approval(str(approval_id), payload.action, approver_id=user.get('sub'), reason=payload.reason)
     if not appv:
         raise HTTPException(status_code=404, detail='Approval not found')
-    return {'id': appv.id, 'status': appv.status}
+    # notify waiting workers via Redis
+    try:
+        import json
+        from redis import Redis
+        REDIS_URL = os.environ.get('REDIS_URL', 'redis://redis:6379/0')
+        redis_conn = Redis.from_url(REDIS_URL)
+        payload_json = json.dumps({'action': appv.status})
+        redis_conn.rpush(f"approval:{appv.id}", payload_json)
+    except Exception as e:
+        # log but don't fail the approval
+        print('Failed to notify redis about approval:', e)
+    return {'id': appv.id, 'status': appv.status}
