"""Read monthly AWS cost data from Cost Explorer."""

import re
from datetime import date
from decimal import Decimal, InvalidOperation


MONTH_PATTERN = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")


def _month_date(value):
    if not isinstance(value, str) or not MONTH_PATTERN.fullmatch(value):
        raise ValueError("Months must use YYYY-MM format.")
    year, month = (int(part) for part in value.split("-"))
    return date(year, month, 1)


def get_time_period(start_month, end_month):
    """Return Cost Explorer's inclusive-start, exclusive-end date range."""
    start = _month_date(start_month)
    end = _month_date(end_month)
    if start > end:
        raise ValueError("The start month must not be later than the end month.")

    if end.month == 12:
        exclusive_end = date(end.year + 1, 1, 1)
    else:
        exclusive_end = date(end.year, end.month + 1, 1)

    return {
        "Start": start.isoformat(),
        "End": exclusive_end.isoformat(),
    }


def _get_regions(client, time_period):
    regions = []
    next_token = None

    while True:
        request = {
            "TimePeriod": time_period,
            "Dimension": "REGION",
            "Context": "COST_AND_USAGE",
        }
        if next_token:
            request["NextPageToken"] = next_token

        response = client.get_dimension_values(**request)
        regions.extend(
            item["Value"]
            for item in response.get("DimensionValues", [])
            if item.get("Value")
        )
        next_token = response.get("NextPageToken")
        if not next_token:
            break

    return sorted(set(regions))


def _account_names(response):
    names = {}
    for item in response.get("DimensionValueAttributes", []):
        attributes = item.get("Attributes", {})
        name = attributes.get("description") or attributes.get("name")
        if item.get("Value") and name:
            names[item["Value"]] = name
    return names


def _query_region(client, region, time_period):
    rows = []
    next_token = None

    while True:
        request = {
            "TimePeriod": time_period,
            "Granularity": "MONTHLY",
            "Metrics": ["UnblendedCost"],
            "GroupBy": [
                {"Type": "DIMENSION", "Key": "LINKED_ACCOUNT"},
                {"Type": "DIMENSION", "Key": "SERVICE"},
            ],
            "Filter": {
                "Dimensions": {
                    "Key": "REGION",
                    "Values": [region],
                }
            },
        }
        if next_token:
            request["NextPageToken"] = next_token

        response = client.get_cost_and_usage(**request)
        names = _account_names(response)

        for period in response.get("ResultsByTime", []):
            month = period.get("TimePeriod", {}).get("Start", "")[:7]
            for group in period.get("Groups", []):
                keys = group.get("Keys", [])
                if len(keys) < 2:
                    continue

                metric = group.get("Metrics", {}).get("UnblendedCost", {})
                try:
                    amount = Decimal(metric.get("Amount", "0"))
                except (InvalidOperation, TypeError):
                    continue

                rows.append(
                    {
                        "month": month,
                        "account_id": keys[0],
                        "account_name": names.get(keys[0], ""),
                        "service": keys[1],
                        "region": region,
                        "amount": amount,
                        "unit": metric.get("Unit", ""),
                        "estimated": bool(period.get("Estimated", False)),
                    }
                )

        next_token = response.get("NextPageToken")
        if not next_token:
            break

    return rows


def query_costs(client, start_month, end_month):
    """Fetch costs grouped by linked account and service for each billed Region.

    Cost Explorer supports at most two GroupBy dimensions. Region is therefore
    queried as a filter, while account and service are the grouping dimensions.
    API failures are returned as warnings so inventory reporting can continue.
    """
    time_period = get_time_period(start_month, end_month)
    warnings = []

    try:
        regions = _get_regions(client, time_period)
    except Exception as error:
        return [], ["Cost Explorer could not list Regions: {}".format(error)]

    rows = []
    for region in regions:
        try:
            rows.extend(_query_region(client, region, time_period))
        except Exception as error:
            warnings.append(
                "Cost Explorer query failed for Region {}: {}".format(region, error)
            )

    rows.sort(
        key=lambda row: (
            row["month"],
            row["account_id"],
            row["service"],
            row["region"],
        )
    )
    return rows, warnings
