import json
import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """
    排程觸發的 Lambda。
    EventBridge Schedule 呼叫時，event 包含觸發時間等 metadata。
    """
    now = datetime.now(timezone.utc).isoformat()
    logger.info(f"排程觸發時間: {now}")
    logger.info(f"Event: {json.dumps(event)}")

    # 模擬定時工作（例如：清理過期資料、發送報告）
    logger.info("執行定時工作中...")

    return {"statusCode": 200, "triggered_at": now}
