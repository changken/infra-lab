import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """
    庫存服務 Worker。
    從 SQS 拉取訊息（Event Source Mapping），訊息 body 是 SNS 包裝過的 JSON。

    SNS → SQS 時，SQS message body 結構：
    {
      "Type": "Notification",
      "MessageId": "...",
      "TopicArn": "arn:aws:sns:...",
      "Subject": "...",
      "Message": "{\"order_id\": \"...\", \"items\": [...]}",  ← 原始訊息在這裡
      "Timestamp": "...",
      "MessageAttributes": { ... }
    }
    """
    for record in event.get("Records", []):
        # SQS record body 是 SNS 的 Notification JSON 字串
        sns_envelope = json.loads(record["body"])
        message = json.loads(sns_envelope["Message"])

        order_id = message.get("order_id", "N/A")
        items = message.get("items", [])

        logger.info(f"[庫存] 處理訂單 {order_id}，扣除 {len(items)} 個品項")
        for item in items:
            logger.info(f"  扣庫存: {item.get('sku')} x {item.get('qty')}")

    return {"statusCode": 200}
