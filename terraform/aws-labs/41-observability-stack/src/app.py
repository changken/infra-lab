import json
import logging
import random
import time

# 結構化 JSON 日誌，方便 CloudWatch Logs Insights 用欄位過濾
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    path = event.get("rawPath", "/")
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    logger.info(
        json.dumps(
            {
                "level": "INFO",
                "event": "request_received",
                "path": path,
                "method": method,
                "request_id": context.aws_request_id,
            }
        )
    )

    try:
        return _route(path, context)
    except Exception as e:
        logger.error(
            json.dumps(
                {
                    "level": "ERROR",
                    "event": "request_failed",
                    "path": path,
                    "error": str(e),
                    "request_id": context.aws_request_id,
                }
            )
        )
        # re-raise → Lambda 記錄 Error metric + X-Ray 標記 Fault segment
        raise


def _route(path, context):
    if path == "/slow":
        # 用於展示 X-Ray Duration 和 CloudWatch Duration P99 指標
        time.sleep(2)
        logger.info(json.dumps({"level": "INFO", "event": "slow_response", "delay_ms": 2000}))
        return _ok({"message": "slow response", "delay_ms": 2000})

    elif path == "/error":
        # 固定錯誤，用於觸發 CloudWatch Alarm 和 X-Ray Error Segment
        raise ValueError("Simulated error - check X-Ray service map and CloudWatch Alarms")

    elif path == "/random":
        # 30% 錯誤率，用於長時間壓測觀察 alarm 狀態變化
        if random.random() < 0.3:
            raise ValueError("Random error (30% rate)")
        return _ok({"message": "lucky!", "path": path})

    else:
        logger.info(json.dumps({"level": "INFO", "event": "success", "path": path}))
        return _ok({"message": "Hello from Observability Lab!", "path": path})


def _ok(body):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
