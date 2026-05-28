import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")

TABLE_NAME = os.environ["ORDERS_TABLE"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)
    processed = 0

    for record in event["Records"]:
        order = json.loads(record["body"], parse_float=Decimal)
        order_id = order["order_id"]

        # Update status and write to DynamoDB
        order["status"] = "PROCESSED"
        table.put_item(Item=order)

        # Notify via SNS
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"新訂單已處理: {order_id}",
            Message=json.dumps(
                {
                    "order_id": order_id,
                    "customer_id": order["customer_id"],
                    "total_amount": order["total_amount"],
                    "items_count": len(order["items"]),
                    "status": "PROCESSED",
                    "created_at": order["created_at"],
                },
                ensure_ascii=False,
                indent=2,
            ),
        )

        processed += 1
        print(f"[OK] order_id={order_id} written to DynamoDB and SNS notified")

    return {"statusCode": 200, "processed": processed}
