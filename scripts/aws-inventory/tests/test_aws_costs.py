import unittest
from decimal import Decimal

import boto3
from botocore.stub import Stubber

from aws_costs import query_costs


class QueryCostsTests(unittest.TestCase):
    def setUp(self):
        self.client = boto3.client(
            "ce",
            region_name="us-east-1",
            aws_access_key_id="test",
            aws_secret_access_key="test",
            aws_session_token="test",
        )

    def test_returns_monthly_costs_by_account_service_and_region(self):
        time_period = {"Start": "2026-01-01", "End": "2026-03-01"}
        cost_request = {
            "TimePeriod": time_period,
            "Granularity": "MONTHLY",
            "Metrics": ["UnblendedCost"],
            "GroupBy": [
                {"Type": "DIMENSION", "Key": "LINKED_ACCOUNT"},
                {"Type": "DIMENSION", "Key": "SERVICE"},
            ],
            "Filter": {
                "Dimensions": {"Key": "REGION", "Values": ["us-east-1"]}
            },
        }
        cost_response = {
            "DimensionValueAttributes": [
                {
                    "Value": "111111111111",
                    "Attributes": {"description": "Personal account"},
                }
            ],
            "ResultsByTime": [
                {
                    "TimePeriod": {"Start": "2026-01-01", "End": "2026-02-01"},
                    "Total": {},
                    "Groups": [
                        {
                            "Keys": ["111111111111", "Amazon Elastic Compute Cloud"],
                            "Metrics": {
                                "UnblendedCost": {"Amount": "12.34", "Unit": "USD"}
                            },
                        }
                    ],
                    "Estimated": False,
                },
                {
                    "TimePeriod": {"Start": "2026-02-01", "End": "2026-03-01"},
                    "Total": {},
                    "Groups": [
                        {
                            "Keys": ["111111111111", "Amazon Elastic Compute Cloud"],
                            "Metrics": {
                                "UnblendedCost": {"Amount": "5.67", "Unit": "USD"}
                            },
                        }
                    ],
                    "Estimated": True,
                },
            ],
        }

        with Stubber(self.client) as stubber:
            stubber.add_response(
                "get_dimension_values",
                {
                    "DimensionValues": [{"Value": "us-east-1"}],
                    "ReturnSize": 1,
                    "TotalSize": 1,
                },
                {
                    "TimePeriod": time_period,
                    "Dimension": "REGION",
                    "Context": "COST_AND_USAGE",
                },
            )
            stubber.add_response(
                "get_cost_and_usage", cost_response, cost_request
            )

            rows, warnings = query_costs(self.client, "2026-01", "2026-02")

        self.assertEqual(warnings, [])
        self.assertEqual(
            rows,
            [
                {
                    "month": "2026-01",
                    "account_id": "111111111111",
                    "account_name": "Personal account",
                    "service": "Amazon Elastic Compute Cloud",
                    "region": "us-east-1",
                    "amount": Decimal("12.34"),
                    "unit": "USD",
                    "estimated": False,
                },
                {
                    "month": "2026-02",
                    "account_id": "111111111111",
                    "account_name": "Personal account",
                    "service": "Amazon Elastic Compute Cloud",
                    "region": "us-east-1",
                    "amount": Decimal("5.67"),
                    "unit": "USD",
                    "estimated": True,
                },
            ],
        )

    def test_rejects_invalid_month_before_calling_aws(self):
        with self.assertRaises(ValueError):
            query_costs(self.client, "2026-13", "2026-14")

    def test_keeps_successful_regions_when_another_region_is_denied(self):
        time_period = {"Start": "2026-01-01", "End": "2026-02-01"}
        denied_request = {
            "TimePeriod": time_period,
            "Granularity": "MONTHLY",
            "Metrics": ["UnblendedCost"],
            "GroupBy": [
                {"Type": "DIMENSION", "Key": "LINKED_ACCOUNT"},
                {"Type": "DIMENSION", "Key": "SERVICE"},
            ],
            "Filter": {
                "Dimensions": {"Key": "REGION", "Values": ["us-west-2"]}
            },
        }

        with Stubber(self.client) as stubber:
            stubber.add_response(
                "get_dimension_values",
                {
                    "DimensionValues": [
                        {"Value": "us-east-1"},
                        {"Value": "us-west-2"},
                    ],
                    "ReturnSize": 2,
                    "TotalSize": 2,
                },
                {
                    "TimePeriod": time_period,
                    "Dimension": "REGION",
                    "Context": "COST_AND_USAGE",
                },
            )
            stubber.add_response(
                "get_cost_and_usage",
                {
                    "ResultsByTime": [
                        {
                            "TimePeriod": {
                                "Start": "2026-01-01",
                                "End": "2026-02-01",
                            },
                            "Total": {},
                            "Groups": [
                                {
                                    "Keys": ["111111111111", "Amazon S3"],
                                    "Metrics": {
                                        "UnblendedCost": {
                                            "Amount": "1.00",
                                            "Unit": "USD",
                                        }
                                    },
                                }
                            ],
                            "Estimated": False,
                        }
                    ]
                },
                {
                    "TimePeriod": time_period,
                    "Granularity": "MONTHLY",
                    "Metrics": ["UnblendedCost"],
                    "GroupBy": [
                        {"Type": "DIMENSION", "Key": "LINKED_ACCOUNT"},
                        {"Type": "DIMENSION", "Key": "SERVICE"},
                    ],
                    "Filter": {
                        "Dimensions": {"Key": "REGION", "Values": ["us-east-1"]}
                    },
                },
            )
            stubber.add_client_error(
                "get_cost_and_usage",
                service_error_code="AccessDeniedException",
                service_message="not authorized",
                expected_params=denied_request,
            )

            rows, warnings = query_costs(self.client, "2026-01", "2026-01")

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["region"], "us-east-1")
        self.assertEqual(len(warnings), 1)
        self.assertIn("us-west-2", warnings[0])


if __name__ == "__main__":
    unittest.main()
