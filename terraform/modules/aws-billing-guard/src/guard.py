"""
aws-billing-guard: Lambda handler
觸發來源: AWS Budgets → SNS → Lambda

流程:
  1. 列出所有 RDS instances（狀態 available）
  2. 對每個 instance 建立 final snapshot
  3. 等待 snapshot 完成後刪除 instance
  4. 記錄結果
"""

import boto3
import logging
import os
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds = boto3.client("rds")


def lambda_handler(event, context):
    logger.info("Billing guard triggered. Event: %s", event)

    dry_run = os.environ.get("DRY_RUN", "false").lower() == "true"
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")

    # 列出所有 available RDS instances
    paginator = rds.get_paginator("describe_db_instances")
    instances = []
    for page in paginator.paginate():
        for db in page["DBInstances"]:
            if db["DBInstanceStatus"] == "available":
                instances.append(db["DBInstanceIdentifier"])

    if not instances:
        logger.info("No available RDS instances found. Nothing to do.")
        return {"status": "no_instances", "instances": []}

    logger.info("Found %d RDS instance(s): %s", len(instances), instances)

    results = []
    for db_id in instances:
        snapshot_id = f"billing-guard-{db_id}-{timestamp}"
        try:
            if dry_run:
                logger.info("[DRY RUN] Would snapshot + delete: %s", db_id)
                results.append({"instance": db_id, "action": "dry_run"})
                continue

            # Step 1: 建立 snapshot
            logger.info("Creating snapshot %s for %s", snapshot_id, db_id)
            rds.create_db_snapshot(
                DBSnapshotIdentifier=snapshot_id,
                DBInstanceIdentifier=db_id,
            )

            # Step 2: 等待 snapshot 完成
            logger.info("Waiting for snapshot %s to complete...", snapshot_id)
            waiter = rds.get_waiter("db_snapshot_completed")
            waiter.wait(
                DBSnapshotIdentifier=snapshot_id,
                WaiterConfig={"Delay": 30, "MaxAttempts": 40},  # 最多等 20 分鐘
            )

            # Step 3: 刪除 instance（skip_final_snapshot=True，因為我們已手動建了）
            logger.info("Deleting RDS instance: %s", db_id)
            rds.delete_db_instance(
                DBInstanceIdentifier=db_id,
                SkipFinalSnapshot=True,
            )

            results.append({"instance": db_id, "snapshot": snapshot_id, "action": "deleted"})
            logger.info("Done: %s → snapshot=%s, deleted", db_id, snapshot_id)

        except Exception as e:
            logger.error("Failed for %s: %s", db_id, str(e))
            results.append({"instance": db_id, "snapshot": snapshot_id, "action": "error", "error": str(e)})

    return {"status": "done", "results": results}
