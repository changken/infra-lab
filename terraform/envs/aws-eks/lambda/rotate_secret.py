"""
Secrets Manager rotation Lambda — self-generated key

4-step rotation protocol:
  createSecret  → generate new random token, store as AWSPENDING
  setSecret     → no-op (self-generated key, no external service to update)
  testSecret    → verify AWSPENDING is valid JSON with expected key
  finishSecret  → promote AWSPENDING to AWSCURRENT
"""

import boto3
import json
import logging
import secrets

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    client = boto3.client("secretsmanager")

    logger.info("rotation step=%s secret=%s", step, arn)

    if step == "createSecret":
        _create_secret(client, arn, token)
    elif step == "setSecret":
        pass  # self-generated key: nothing to push to external service
    elif step == "testSecret":
        _test_secret(client, arn, token)
    elif step == "finishSecret":
        _finish_secret(client, arn, token)
    else:
        raise ValueError(f"Unknown rotation step: {step}")


def _create_secret(client, arn, token):
    # If AWSPENDING already exists for this token, skip (idempotent)
    try:
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
        logger.info("AWSPENDING already exists for token %s, skipping createSecret", token)
        return
    except client.exceptions.ResourceNotFoundException:
        pass

    # Read current secret to preserve other keys in the JSON object
    current = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")["SecretString"]
    )

    # Generate cryptographically secure random key (32 hex chars = 128 bits)
    current["chat-api-key"] = secrets.token_hex(16)

    client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(current),
        VersionStages=["AWSPENDING"],
    )
    logger.info("created AWSPENDING with new chat-api-key")


def _test_secret(client, arn, token):
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")[
            "SecretString"
        ]
    )
    if "chat-api-key" not in pending or not pending["chat-api-key"]:
        raise ValueError("AWSPENDING secret is missing or empty chat-api-key")
    logger.info("AWSPENDING secret validated OK")


def _finish_secret(client, arn, token):
    metadata = client.describe_secret(SecretId=arn)

    # Find the current AWSCURRENT version (to demote it)
    current_version = None
    for version_id, stages in metadata["VersionIdsToStages"].items():
        if "AWSCURRENT" in stages:
            if version_id == token:
                logger.info("version %s is already AWSCURRENT, nothing to do", token)
                return
            current_version = version_id
            break

    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
    logger.info("promoted %s to AWSCURRENT (demoted %s)", token, current_version)
