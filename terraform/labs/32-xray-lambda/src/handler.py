import json
import time


def handler(event, context):
    time.sleep(0.1)  # 模擬業務延遲，讓 X-Ray trace 有意義的數字
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Hello from X-Ray lab!",
            "path": event.get("path", "/"),
        }),
    }
