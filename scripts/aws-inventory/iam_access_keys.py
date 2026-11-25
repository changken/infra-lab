#!/usr/bin/env python3
"""Collect IAM access-key metadata by enumerating IAM users first."""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import boto3


def _iter_pages(operation, result_key, request):
    request = dict(request)
    while True:
        response = operation(**request)
        yield from response.get(result_key, [])
        if not response.get("IsTruncated"):
            return

        marker = response.get("Marker")
        if not marker:
            raise RuntimeError(
                "AWS marked {} response truncated without a Marker.".format(
                    result_key
                )
            )
        request["Marker"] = marker


def collect_iam_data(client):
    """Return IAM users, their access-key metadata, and per-user warnings."""
    try:
        users = list(_iter_pages(client.list_users, "Users", {}))
    except Exception as error:
        return [], [], ["IAM user listing failed: {}".format(error)]

    rows = []
    warnings = []
    for user in users:
        user_name = user.get("UserName")
        if not user_name:
            continue
        try:
            keys = _iter_pages(
                client.list_access_keys,
                "AccessKeyMetadata",
                {"UserName": user_name},
            )
            rows.extend(
                dict(key, UserName=user_name)
                for key in keys
            )
        except Exception as error:
            warnings.append(
                "IAM access-key query failed for {}: {}".format(user_name, error)
            )

    return users, rows, warnings


def _json_default(value):
    if isinstance(value, datetime):
        return value.isoformat()
    raise TypeError("Object of type {} is not JSON serializable".format(type(value)))


def write_iam_inventory(output_dir, timestamp, users, access_keys):
    """Write explicit JSON files, including when the result lists are empty."""
    directory = Path(output_dir) / timestamp / "global"
    directory.mkdir(parents=True, exist_ok=True)
    for name, rows in (
        ("iam-list_users.json", users),
        ("iam-list_access_keys.json", access_keys),
    ):
        (directory / name).write_text(
            json.dumps(rows, ensure_ascii=False, indent=2, default=_json_default),
            encoding="utf-8",
        )
    return directory


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args(argv)

    try:
        session = boto3.Session(profile_name=args.profile)
        client = session.client("iam", region_name="us-east-1")
        users, rows, warnings = collect_iam_data(client)
    except Exception as error:
        print("IAM access-key collection failed: {}".format(error), file=sys.stderr)
        return 1

    timestamp = datetime.now().isoformat(timespec="minutes").replace(":", "-")
    write_iam_inventory(args.output_dir, timestamp, users, rows)

    print(
        "IAM inventory for profile {}: {} users, {} access keys.".format(
            args.profile, len(users), len(rows)
        )
    )
    for warning in warnings:
        print(warning, file=sys.stderr)
    return 1 if warnings else 0


if __name__ == "__main__":
    raise SystemExit(main())
