import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """
    SQS 消費者 Lambda。
    SQS Event Source Mapping 會把訊息包成 Records 陣列傳進來。
    """
    records = event.get("Records", [])
    logger.info(f"收到 {len(records)} 筆訊息")

    for record in records:
        message_id = record["messageId"]
        body = record["body"]

        # 嘗試解析 JSON，不是 JSON 就直接印原文
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = body

        logger.info(f"[{message_id}] 處理訊息: {payload}")

        # 模擬處理邏輯
        # ⚠️ 若這裡拋出例外，Lambda 會回傳錯誤
        #    SQS 會讓訊息的 visibility timeout 到期後重新可見
        #    重試超過 max_receive_count 次 → 移入 DLQ

    return {"statusCode": 200, "processed": len(records)}
