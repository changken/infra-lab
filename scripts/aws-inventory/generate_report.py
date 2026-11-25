#!/usr/bin/env python3
"""Query Cost Explorer and build the report for one inventory run."""

import argparse
from datetime import datetime
from pathlib import Path

import boto3

from aws_costs import query_costs
from workbook import create_workbook


def _parse_profile_account(value):
    profile, separator, account_id = value.partition("=")
    if not separator or not profile or not account_id:
        raise argparse.ArgumentTypeError(
            "Profile/account values must use PROFILE=ACCOUNT_ID."
        )
    return {"profile": profile, "account_id": account_id}


def _report_path(run_dir, run_timestamp):
    run_time = datetime.strptime(run_timestamp, "%Y%m%dT%H%M%S")
    name = run_time.strftime("aws-report-%Y-%m-%d-%H-%M-%S.xlsx")
    return Path(run_dir) / name


def generate_report(
    run_dir,
    run_timestamp,
    profile_accounts,
    regions,
    categories,
    cost_profile,
    cost_account_id,
    start_month,
    end_month,
):
    run_dir = Path(run_dir)
    cost_rows = []
    cost_warnings = []

    try:
        session = boto3.Session(profile_name=cost_profile)
        client = session.client("ce", region_name="us-east-1")
        cost_rows, cost_warnings = query_costs(client, start_month, end_month)
    except Exception as error:
        cost_warnings.append("Cost Explorer 查詢失敗：{}".format(error))

    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    metadata = {
        "run_timestamp": run_timestamp,
        "generated_at": generated_at,
        "profiles": profile_accounts,
        "regions": regions,
        "categories": categories,
        "cost_profile": cost_profile,
        "cost_account_id": cost_account_id,
        "cost_start_month": start_month,
        "cost_end_month": end_month,
    }
    output_path = _report_path(run_dir, run_timestamp)
    create_workbook(
        run_dir=run_dir,
        output_path=output_path,
        metadata=metadata,
        cost_rows=cost_rows,
        cost_warnings=cost_warnings,
    )
    return output_path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--run-timestamp", required=True)
    parser.add_argument(
        "--profile-account",
        action="append",
        type=_parse_profile_account,
        default=[],
    )
    parser.add_argument("--region", action="append", default=[])
    parser.add_argument("--category", action="append", default=[])
    parser.add_argument("--cost-profile", required=True)
    parser.add_argument("--cost-account-id", default="")
    parser.add_argument("--start-month", required=True)
    parser.add_argument("--end-month", required=True)
    args = parser.parse_args(argv)

    output_path = generate_report(
        run_dir=args.run_dir,
        run_timestamp=args.run_timestamp,
        profile_accounts=args.profile_account,
        regions=args.region,
        categories=args.category,
        cost_profile=args.cost_profile,
        cost_account_id=args.cost_account_id,
        start_month=args.start_month,
        end_month=args.end_month,
    )
    print("[OK] Excel 報表：{}".format(output_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
