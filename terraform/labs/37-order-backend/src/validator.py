import json
import boto3
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

sqs = boto3.client("sqs")
QUEUE_URL = os.environ["ORDER_QUEUE_URL"]

REQUIRED_FIELDS = ["customer_id", "items", "total_amount"]


def lambda_handler(event, context):
    # Parse request body
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON in request body"})

    # Validate required fields
    missing = [f for f in REQUIRED_FIELDS if f not in body]
    if missing:
        return _response(400, {"error": f"Missing required fields: {missing}"})

    if not isinstance(body["items"], list) or len(body["items"]) == 0:
        return _response(400, {"error": "items must be a non-empty list"})

    # Build order object
    order = {
        "order_id": str(uuid.uuid4()),
        "customer_id": str(body["customer_id"]),
        "items": body["items"],
        "total_amount": Decimal(str(body["total_amount"])),
        "status": "PENDING",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    # Send to SQS for async processing
    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(order),
        MessageAttributes={
            "source": {"StringValue": "validator", "DataType": "String"}
        },
    )

    return _response(201, {"order_id": order["order_id"], "status": "PENDING"})


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
