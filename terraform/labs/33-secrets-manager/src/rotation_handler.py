import boto3
import json
import os
import secrets
import string


def handler(event, context):
    secret_id = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    client = boto3.client("secretsmanager")

    if step == "createSecret":
        _create_secret(client, secret_id, token)
    elif step == "setSecret":
        _set_secret(client, secret_id, token)
    elif step == "testSecret":
        _test_secret(client, secret_id, token)
    elif step == "finishSecret":
        _finish_secret(client, secret_id, token)
    else:
        raise ValueError(f"Unknown rotation step: {step}")


def _create_secret(client, secret_id, token):
    # Idempotency check: AWSPENDING might already exist from a previous retry
    try:
        client.get_secret_value(
            SecretId=secret_id,
            VersionStage="AWSPENDING",
            VersionId=token,
        )
        return
    except client.exceptions.ResourceNotFoundException:
        pass

    # Preserve username from current secret
    current_str = client.get_secret_value(
        SecretId=secret_id,
        VersionStage="AWSCURRENT",
    )["SecretString"]
    current = json.loads(current_str)

    # Generate cryptographically random 32-char password
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    new_password = "".join(secrets.choice(alphabet) for _ in range(32))

    client.put_secret_value(
        SecretId=secret_id,
        ClientRequestToken=token,
        SecretString=json.dumps({
            "username": current["username"],
            "password": new_password,
        }),
        VersionStages=["AWSPENDING"],
    )


def _set_secret(client, secret_id, token):
    # no-op: this lab has no real DB to update.
    # In production: connect to DB and ALTER USER with the AWSPENDING password.
    pass


def _test_secret(client, secret_id, token):
    # Verify AWSPENDING secret has expected shape
    secret_str = client.get_secret_value(
        SecretId=secret_id,
        VersionStage="AWSPENDING",
        VersionId=token,
    )["SecretString"]
    secret = json.loads(secret_str)

    if "username" not in secret:
        raise ValueError("AWSPENDING secret missing 'username' field")
    if "password" not in secret:
        raise ValueError("AWSPENDING secret missing 'password' field")
    if len(secret["password"]) < 32:
        raise ValueError("AWSPENDING password is too short")


def _finish_secret(client, secret_id, token):
    # Find the current AWSCURRENT version ID
    metadata = client.describe_secret(SecretId=secret_id)
    current_version = None
    for version_id, stages in metadata.get("VersionIdsToStages", {}).items():
        if "AWSCURRENT" in stages:
            if version_id == token:
                return  # Already promoted — idempotent
            current_version = version_id
            break

    # Promote AWSPENDING → AWSCURRENT (old AWSCURRENT → AWSPREVIOUS automatically)
    client.update_secret_version_stage(
        SecretId=secret_id,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
