import base64
import json
import os
from datetime import datetime, timezone

import boto3

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["TABLE_NAME"]
table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    """
    Processes a batch of Kinesis records and aggregates event_type counts
    into DynamoDB using atomic ADD.

    Each Kinesis record has:
      record["kinesis"]["data"]            → base64-encoded JSON payload
      record["kinesis"]["sequenceNumber"]  → unique per shard
      record["kinesis"]["partitionKey"]    → used for shard routing

    Lambda Event Source Mapping delivers up to `batch_size` records per call.
    """
    print(f"Processing batch of {len(event['Records'])} records")

    counts: dict[str, int] = {}
    for record in event["Records"]:
        raw = base64.b64decode(record["kinesis"]["data"]).decode("utf-8")
        payload = json.loads(raw)
        event_type = payload.get("event_type", "unknown")
        counts[event_type] = counts.get(event_type, 0) + 1

    now = datetime.now(timezone.utc).isoformat()

    for event_type, count in counts.items():
        table.update_item(
            Key={"event_type": event_type},
            UpdateExpression="ADD #cnt :n SET #ts = :ts",
            ExpressionAttributeNames={"#cnt": "count", "#ts": "last_updated"},
            ExpressionAttributeValues={":n": count, ":ts": now},
        )

    print(f"Aggregated: {counts}")
    # Returning an empty batchItemFailures list signals all records succeeded.
    # If an exception propagates instead, the ESM retries the batch (or bisects it).
    return {"batchItemFailures": []}
