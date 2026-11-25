import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

import boto3
from botocore.stub import Stubber

from iam_access_keys import collect_iam_data, write_iam_inventory


def user(user_name):
    return {
        "Path": "/",
        "UserName": user_name,
        "UserId": "AIDAEXAMPLE" + user_name.upper().ljust(8, "X"),
        "Arn": "arn:aws:iam::111111111111:user/" + user_name,
        "CreateDate": datetime(2026, 1, 1, tzinfo=timezone.utc),
    }


class IamAccessKeyScanConfigTests(unittest.TestCase):
    def test_dynamic_iam_operations_are_not_in_the_unparameterized_scan(self):
        security_scan = (
            Path(__file__).parents[1] / "scans" / "security.json"
        )
        entries = json.loads(security_scan.read_text(encoding="utf-8"))

        dynamically_scanned = [
            entry
            for entry in entries
            if entry.get("service") == "iam"
            and entry.get("function") in {"list_users", "list_access_keys"}
        ]

        self.assertEqual(dynamically_scanned, [])


class CollectAccessKeysTests(unittest.TestCase):
    def setUp(self):
        self.client = boto3.client(
            "iam",
            region_name="us-east-1",
            aws_access_key_id="test",
            aws_secret_access_key="test",
            aws_session_token="test",
        )

    def test_lists_keys_for_each_user_and_paginates_users(self):
        created = datetime(2026, 1, 1, tzinfo=timezone.utc)
        with Stubber(self.client) as stubber:
            stubber.add_response(
                "list_users",
                {
                    "Users": [user("alice")],
                    "IsTruncated": True,
                    "Marker": "next-user",
                },
                {},
            )
            stubber.add_response(
                "list_users",
                {"Users": [user("bob")], "IsTruncated": False},
                {"Marker": "next-user"},
            )
            stubber.add_response(
                "list_access_keys",
                {
                    "AccessKeyMetadata": [
                        {
                            "UserName": "alice",
                            "AccessKeyId": "AKIAEXAMPLE000001",
                            "Status": "Active",
                            "CreateDate": created,
                        }
                    ],
                    "IsTruncated": False,
                },
                {"UserName": "alice"},
            )
            stubber.add_response(
                "list_access_keys",
                {"AccessKeyMetadata": [], "IsTruncated": False},
                {"UserName": "bob"},
            )

            users, rows, warnings = collect_iam_data(self.client)

        self.assertEqual(warnings, [])
        self.assertEqual([item["UserName"] for item in users], ["alice", "bob"])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["UserName"], "alice")
        self.assertEqual(rows[0]["AccessKeyId"], "AKIAEXAMPLE000001")

    def test_keeps_other_users_when_one_users_key_query_fails(self):
        with Stubber(self.client) as stubber:
            stubber.add_response(
                "list_users",
                {
                    "Users": [user("alice"), user("bob")],
                    "IsTruncated": False,
                },
                {},
            )
            stubber.add_client_error(
                "list_access_keys",
                service_error_code="AccessDenied",
                service_message="denied",
                expected_params={"UserName": "alice"},
            )
            stubber.add_response(
                "list_access_keys",
                {
                    "AccessKeyMetadata": [
                        {
                            "UserName": "bob",
                            "AccessKeyId": "AKIABOB0000000001",
                            "Status": "Inactive",
                        }
                    ],
                    "IsTruncated": False,
                },
                {"UserName": "bob"},
            )

            users, rows, warnings = collect_iam_data(self.client)

        self.assertEqual(len(users), 2)
        self.assertEqual([row["UserName"] for row in rows], ["bob"])
        self.assertEqual(len(warnings), 1)
        self.assertIn("alice", warnings[0])

    def test_writes_empty_user_and_key_results_explicitly(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            output_dir = write_iam_inventory(
                temp_dir,
                "2026-11-25T12-00",
                users=[],
                access_keys=[],
            )

            self.assertEqual(
                json.loads((output_dir / "iam-list_users.json").read_text()),
                [],
            )
            self.assertEqual(
                json.loads((output_dir / "iam-list_access_keys.json").read_text()),
                [],
            )


if __name__ == "__main__":
    unittest.main()
