import json
import os
import uuid
from datetime import datetime

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def handler(event, context):
    method = event["requestContext"]["http"]["method"]
    path = event["requestContext"]["http"]["path"]
    path_params = event.get("pathParameters") or {}

    try:
        if method == "GET" and path == "/items":
            return list_items()
        elif method == "GET" and "item_id" in path_params:
            return get_item(path_params["item_id"])
        elif method == "POST" and path == "/items":
            body = json.loads(event.get("body") or "{}")
            return create_item(body)
        elif method == "DELETE" and "item_id" in path_params:
            return delete_item(path_params["item_id"])
        else:
            return resp(404, {"error": "Not found"})
    except Exception as e:
        return resp(500, {"error": str(e)})


def list_items():
    result = table.scan()
    return resp(200, {"items": result["Items"]})


def get_item(item_id):
    result = table.get_item(Key={"item_id": item_id})
    item = result.get("Item")
    if not item:
        return resp(404, {"error": "Item not found"})
    return resp(200, item)


def create_item(body):
    item = {
        "item_id": str(uuid.uuid4()),
        "name": body.get("name", "unnamed"),
        "description": body.get("description", ""),
        "created_at": datetime.utcnow().isoformat(),
    }
    table.put_item(Item=item)
    return resp(201, item)


def delete_item(item_id):
    table.delete_item(Key={"item_id": item_id})
    return resp(200, {"message": f"Item {item_id} deleted"})


def resp(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }
