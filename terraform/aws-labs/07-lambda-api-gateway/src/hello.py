import json
import os


def handler(event, context):
    # API Gateway 把 HTTP 請求包在 event 裡傳進來
    query_params = event.get("queryStringParameters") or {}
    name = query_params.get("name", "World")
    method = event.get("requestContext", {}).get("http", {}).get("method", "?")
    path = event.get("requestContext", {}).get("http", {}).get("path", "?")

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": f"Hello, {name}!",
            "method": method,
            "path": path,
            "environment": os.environ.get("ENVIRONMENT", "unknown"),
        }),
    }
