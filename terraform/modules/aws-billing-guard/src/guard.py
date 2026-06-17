"""
aws-billing-guard: Lambda handler
觸發來源: AWS Budgets → SNS → Lambda

流程:
  1. 停止所有 running EC2 instances
  2. 刪除所有 ALB/NLB 的 Listeners（ELB 本身無法停止，刪 listener 停止流量計費）
  3. 列出所有 RDS instances（狀態 available）→ snapshot + delete
  4. 記錄結果
"""

import boto3
import logging
import os
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
elbv2 = boto3.client("elbv2")
rds = boto3.client("rds")


def stop_ec2_instances(dry_run: bool) -> list:
    results = []
    resp = ec2.describe_instances(
        Filters=[{"Name": "instance-state-name", "Values": ["running"]}]
    )
    instance_ids = [
        i["InstanceId"]
        for r in resp["Reservations"]
        for i in r["Instances"]
    ]

    if not instance_ids:
        logger.info("No running EC2 instances found.")
        return results

    logger.info("Found %d running EC2 instance(s): %s", len(instance_ids), instance_ids)

    if dry_run:
        for iid in instance_ids:
            logger.info("[DRY RUN] Would stop EC2: %s", iid)
            results.append({"resource": iid, "type": "ec2", "action": "dry_run"})
    else:
        ec2.stop_instances(InstanceIds=instance_ids)
        for iid in instance_ids:
            logger.info("Stopped EC2: %s", iid)
            results.append({"resource": iid, "type": "ec2", "action": "stopped"})

    return results


def delete_elb_listeners(dry_run: bool) -> list:
    results = []
    lbs = elbv2.describe_load_balancers()["LoadBalancers"]

    if not lbs:
        logger.info("No load balancers found.")
        return results

    for lb in lbs:
        lb_arn = lb["LoadBalancerArn"]
        lb_name = lb["LoadBalancerName"]
        listeners = elbv2.describe_listeners(LoadBalancerArn=lb_arn)["Listeners"]

        for listener in listeners:
            l_arn = listener["ListenerArn"]
            port = listener["Port"]
            if dry_run:
                logger.info("[DRY RUN] Would delete listener port=%s on %s", port, lb_name)
                results.append({"resource": lb_name, "type": "elb_listener", "port": port, "action": "dry_run"})
            else:
                elbv2.delete_listener(ListenerArn=l_arn)
                logger.info("Deleted listener port=%s on %s", port, lb_name)
                results.append({"resource": lb_name, "type": "elb_listener", "port": port, "action": "deleted"})

    return results


def snapshot_and_delete_rds(dry_run: bool) -> list:
    results = []
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")

    paginator = rds.get_paginator("describe_db_instances")
    instances = []
    for page in paginator.paginate():
        for db in page["DBInstances"]:
            if db["DBInstanceStatus"] == "available":
                instances.append(db["DBInstanceIdentifier"])

    if not instances:
        logger.info("No available RDS instances found.")
        return results

    logger.info("Found %d RDS instance(s): %s", len(instances), instances)

    for db_id in instances:
        snapshot_id = f"billing-guard-{db_id}-{timestamp}"
        try:
            if dry_run:
                logger.info("[DRY RUN] Would snapshot + delete RDS: %s", db_id)
                results.append({"resource": db_id, "type": "rds", "action": "dry_run"})
                continue

            logger.info("Creating snapshot %s for %s", snapshot_id, db_id)
            rds.create_db_snapshot(
                DBSnapshotIdentifier=snapshot_id,
                DBInstanceIdentifier=db_id,
            )

            logger.info("Waiting for snapshot %s to complete...", snapshot_id)
            waiter = rds.get_waiter("db_snapshot_completed")
            waiter.wait(
                DBSnapshotIdentifier=snapshot_id,
                WaiterConfig={"Delay": 30, "MaxAttempts": 40},
            )

            logger.info("Deleting RDS instance: %s", db_id)
            rds.delete_db_instance(
                DBInstanceIdentifier=db_id,
                SkipFinalSnapshot=True,
            )

            results.append({"resource": db_id, "type": "rds", "snapshot": snapshot_id, "action": "deleted"})
            logger.info("Done: %s → snapshot=%s, deleted", db_id, snapshot_id)

        except Exception as e:
            logger.error("Failed for RDS %s: %s", db_id, str(e))
            results.append({"resource": db_id, "type": "rds", "action": "error", "error": str(e)})

    return results


def lambda_handler(event, context):
    logger.info("Billing guard triggered. Event: %s", event)
    dry_run = os.environ.get("DRY_RUN", "false").lower() == "true"

    results = []
    results += stop_ec2_instances(dry_run)
    results += delete_elb_listeners(dry_run)
    results += snapshot_and_delete_rds(dry_run)

    logger.info("Billing guard complete. Results: %s", results)
    return {"status": "done", "dry_run": dry_run, "results": results}
