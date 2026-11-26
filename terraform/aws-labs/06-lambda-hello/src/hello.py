import json
import os


def handler(event, context):
    name = event.get("name", "World")
    env = os.environ.get("ENVIRONMENT", "unknown")

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": f"Hello, {name}!",
            "environment": env,
        }),
    }
