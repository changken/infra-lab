"""
aws-rds-scheduler: Lambda handler
觸發來源: EventBridge Scheduler → Lambda

環境變數:
  ACTION        - "stop" 或 "start"
  SNS_TOPIC_ARN - 通知用 SNS topic ARN
"""

import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds = boto3.client("rds")
sns = boto3.client("sns")

ACTION = os.environ["ACTION"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def lambda_handler(event, context):
    paginator = rds.get_paginator("describe_db_instances")
    results = []

    for page in paginator.paginate():
        for db in page["DBInstances"]:
            db_id = db["DBInstanceIdentifier"]
            status = db["DBInstanceStatus"]

            try:
                if ACTION == "stop" and status == "available":
                    rds.stop_db_instance(DBInstanceIdentifier=db_id)
                    results.append(f"STOPPED: {db_id}")
                    logger.info("Stopped: %s", db_id)

                elif ACTION == "start" and status == "stopped":
                    rds.start_db_instance(DBInstanceIdentifier=db_id)
                    results.append(f"STARTED: {db_id}")
                    logger.info("Started: %s", db_id)

                else:
                    logger.info("Skipped %s (status=%s, action=%s)", db_id, status, ACTION)

            except Exception as e:
                msg = f"ERROR {ACTION} {db_id}: {e}"
                results.append(msg)
                logger.error(msg)

    if results:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[RDS Scheduler] {ACTION.upper()} completed",
            Message="\n".join(results),
        )

    return {"action": ACTION, "results": results}
