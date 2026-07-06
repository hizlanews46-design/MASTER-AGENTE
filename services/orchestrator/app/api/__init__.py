@@
-    # notify waiting workers via Redis
-    try:
-        import json
-        from redis import Redis
-        REDIS_URL = os.environ.get('REDIS_URL', 'redis://redis:6379/0')
-        redis_conn = Redis.from_url(REDIS_URL)
-        payload_json = json.dumps({'action': appv.status})
-        redis_conn.rpush(f"approval:{appv.id}", payload_json)
-    except Exception as e:
-        # log but don't fail the approval
-        print('Failed to notify redis about approval:', e)
+    # notify waiting workers via Redis pub/sub
+    try:
+        import json
+        from redis import Redis
+        REDIS_URL = os.environ.get('REDIS_URL', 'redis://redis:6379/0')
+        redis_conn = Redis.from_url(REDIS_URL)
+        payload_json = json.dumps({'action': appv.status})
+        redis_conn.publish(f"approval:{appv.id}", payload_json)
+    except Exception as e:
+        # log but don't fail the approval
+        print('Failed to publish redis approval message:', e)
     return {'id': appv.id, 'status': appv.status}
