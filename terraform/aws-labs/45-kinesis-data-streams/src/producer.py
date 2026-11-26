import json
import os
import random
import time

import boto3

kinesis = boto3.client("kinesis")
STREAM_NAME = os.environ["STREAM_NAME"]

EVENT_TYPES = ["page_view", "button_click", "purchase", "search", "logout"]


def handler(event, context):
    """
    Accepts POST body to put events onto Kinesis, or generates a random batch.

    Body examples:
      {}                        → generate 10 random events
      {"count": 50}             → generate 50 random events
      {"event_type": "purchase", "user_id": "u-42", "amount": 99.9}
                                → put exactly one custom event
    """
    body = event.get("body") or "{}"
    try:
        payload = json.loads(body) if isinstance(body, str) else (body or {})
    except json.JSONDecodeError:
        payload = {}

    if "event_type" in payload:
        records = [payload]
    else:
        count = min(int(payload.get("count", 10)), 500)
        records = [
            {
                "event_type": random.choice(EVENT_TYPES),
                "user_id": f"user-{random.randint(1, 200)}",
                "timestamp": int(time.time() * 1000),
                "session_id": f"sess-{random.randint(1000, 9999)}",
            }
            for _ in range(count)
        ]

    kinesis_records = [
        {"Data": json.dumps(r), "PartitionKey": r.get("user_id", "default")}
        for r in records
    ]

    response = kinesis.put_records(StreamName=STREAM_NAME, Records=kinesis_records)

    failed = response.get("FailedRecordCount", 0)
    print(f"Put {len(records)} records, {failed} failed, stream={STREAM_NAME}")

    return {
        "statusCode": 200,
        "body": json.dumps({"sent": len(records) - failed, "failed": failed}),
    }
