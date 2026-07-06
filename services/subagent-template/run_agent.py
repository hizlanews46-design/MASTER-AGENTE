import os, time, json

spec = json.loads(os.environ.get("AGENT_SPEC", "{}"))
print("Starting sub-agent:", spec.get("name"))
# connect to qdrant, postgres, model provider per spec
# placeholder: simulate work and checkpointing
for i in range(3):
    print(f"working... step {i+1}")
    time.sleep(1)
print("Sub-agent finished")
