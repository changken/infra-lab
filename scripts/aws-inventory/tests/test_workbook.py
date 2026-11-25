import json
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from decimal import Decimal

from workbook import create_workbook


MAIN_NS = {"main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def table_columns(archive, table_name):
    for name in archive.namelist():
        if name.startswith("xl/tables/") and name.endswith(".xml"):
            root = ET.fromstring(archive.read(name))
            if root.attrib.get("name") == table_name:
                return [
                    column.attrib["name"]
                    for column in root.findall("main:tableColumns/main:tableColumn", MAIN_NS)
                ], root.attrib["ref"], root
    raise AssertionError("Excel table was not written: {}".format(table_name))


def shared_strings(archive):
    root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
    return [
        "".join(text.text or "" for text in item.findall(".//main:t", MAIN_NS))
        for item in root.findall("main:si", MAIN_NS)
    ]


class WorkbookTests(unittest.TestCase):
    def test_creates_readable_filtered_workbook_and_links_source_json(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            run_dir = Path(temp_dir) / "inventory-output" / "20261125T120000"
            bucket_json = (
                run_dir
                / "111111111111"
                / "storage"
                / "2026-11-25T12-00"
                / "us-east-1"
                / "s3-list_buckets.json"
            )
            duplicate_bucket_json = (
                run_dir
                / "111111111111"
                / "storage"
                / "2026-11-25T12-00"
                / "us-west-2"
                / "s3-list_buckets.json"
            )
            instance_json = (
                run_dir
                / "111111111111"
                / "billing"
                / "2026-11-25T12-00"
                / "us-east-1"
                / "ec2-describe_instances.json"
            )
            access_key_json = (
                run_dir
                / "111111111111"
                / "security"
                / "2026-11-25T12-00"
                / "global"
                / "iam-list_access_keys.json"
            )
            user_json = access_key_json.with_name("iam-list_users.json")
            for path in (
                bucket_json,
                duplicate_bucket_json,
                instance_json,
                access_key_json,
                user_json,
            ):
                path.parent.mkdir(parents=True, exist_ok=True)

            bucket_payload = [
                {
                    "Name": "personal-site",
                    "CreationDate": "2025-07-28T13:09:39+00:00",
                    "BucketArn": "arn:aws:s3:::personal-site",
                }
            ]
            bucket_json.write_text(json.dumps(bucket_payload), encoding="utf-8")
            duplicate_bucket_json.write_text(json.dumps(bucket_payload), encoding="utf-8")
            instance_json.write_text(
                json.dumps(
                    [
                        {
                            "Instances": [
                                {
                                    "InstanceId": "i-0123456789abcdef0",
                                    "InstanceType": "t3.micro",
                                    "State": {"Name": "running"},
                                    "PrivateIpAddress": "10.0.0.10",
                                    "Placement": {"AvailabilityZone": "us-east-1a"},
                                }
                            ]
                        }
                    ]
                ),
                encoding="utf-8",
            )
            access_key_json.write_text(
                json.dumps(
                    [
                        {
                            "UserName": "alice",
                            "AccessKeyId": "AKIAEXAMPLE000001",
                            "Status": "Active",
                        }
                    ]
                ),
                encoding="utf-8",
            )
            user_json.write_text(
                json.dumps(
                    [
                        {
                            "UserName": "alice",
                            "UserId": "AIDAEXAMPLEUSER00001",
                            "Arn": "arn:aws:iam::111111111111:user/alice",
                        }
                    ]
                ),
                encoding="utf-8",
            )

            output_path = run_dir / "aws-report-2026-11-25-12-00-00.xlsx"
            metadata = {
                "run_timestamp": "20261125T120000",
                "profiles": [
                    {"profile": "org-management", "account_id": "111111111111"}
                ],
                "regions": ["us-east-1", "us-west-2"],
                "categories": ["billing", "storage"],
                "cost_start_month": "2026-10",
                "cost_end_month": "2026-11",
            }
            costs = [
                {
                    "month": "2026-10",
                    "account_id": "111111111111",
                    "account_name": "Personal account",
                    "service": "Amazon S3",
                    "region": "us-east-1",
                    "amount": Decimal("1.25"),
                    "unit": "USD",
                    "estimated": False,
                }
            ]

            create_workbook(
                run_dir=run_dir,
                output_path=output_path,
                metadata=metadata,
                cost_rows=costs,
                scan_warnings=[],
                cost_warnings=[],
            )

            self.assertTrue(zipfile.is_zipfile(output_path))
            with zipfile.ZipFile(output_path) as archive:
                workbook_xml = ET.fromstring(archive.read("xl/workbook.xml"))
                sheet_names = [
                    sheet.attrib["name"]
                    for sheet in workbook_xml.findall("main:sheets/main:sheet", MAIN_NS)
                ]
                self.assertEqual(sheet_names, ["總覽", "資源清單", "費用明細"])

                resource_headers, resource_range, resource_table = table_columns(
                    archive, "InventoryTable"
                )
                self.assertEqual(
                    resource_headers,
                    [
                        "Profile",
                        "AWS 帳號 ID",
                        "資源類別",
                        "AWS 服務",
                        "資源類型",
                        "資源名稱",
                        "資源 ID",
                        "Region",
                        "狀態",
                        "建立／更新時間",
                        "ARN",
                        "Tags",
                        "主要資訊",
                        "原始 JSON",
                    ],
                )
                self.assertEqual(resource_range, "A1:N5")
                self.assertIsNotNone(resource_table.find("main:autoFilter", MAIN_NS))

                resource_sheet = ET.fromstring(
                    archive.read("xl/worksheets/sheet2.xml")
                )
                self.assertTrue(
                    resource_sheet.findall("main:conditionalFormatting", MAIN_NS)
                )

                cost_headers, cost_range, _ = table_columns(archive, "CostsTable")
                self.assertEqual(
                    cost_headers,
                    [
                        "費用月份",
                        "AWS 帳號 ID",
                        "帳號名稱",
                        "服務",
                        "Region",
                        "費用金額",
                        "幣別",
                        "是否為估算",
                    ],
                )
                self.assertEqual(cost_range, "A1:H2")

                strings = shared_strings(archive)
                self.assertIn("personal-site", strings)
                self.assertIn("Global", strings)
                self.assertIn("AKIAEXAMPLE000001", strings)
                self.assertIn("IAM User", strings)
                self.assertTrue(any("t3.micro" in value for value in strings))

                relationship_files = [
                    name
                    for name in archive.namelist()
                    if name.startswith("xl/worksheets/_rels/")
                ]
                relationships = "\n".join(
                    archive.read(name).decode("utf-8") for name in relationship_files
                )
                self.assertIn("s3-list_buckets.json", relationships)
                self.assertIn("TargetMode=\"External\"", relationships)

    def test_creates_workbook_for_empty_results_and_exposes_cost_warnings(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            run_dir = Path(temp_dir) / "inventory-output" / "20261125T130000"
            run_dir.mkdir(parents=True)
            account_log = (
                run_dir / "111111111111" / "storage" / "aws_resources_2026-11.log"
            )
            account_log.parent.mkdir(parents=True)
            account_log.write_text(
                "2026-11-25 - aws_auto_inventory - ERROR - "
                "Error while processing s3, us-east-1.\n",
                encoding="utf-8",
            )
            (run_dir / "scan-errors.tsv").write_text(
                "org-management\t111111111111\tstorage\t執行失敗\t"
                "Inventory scanner returned a non-zero exit code.\n",
                encoding="utf-8",
            )
            output_path = run_dir / "aws-report-2026-11-25-13-00-00.xlsx"

            create_workbook(
                run_dir=run_dir,
                output_path=output_path,
                metadata={
                    "run_timestamp": "20261125T130000",
                    "profiles": [
                        {"profile": "org-management", "account_id": "111111111111"}
                    ],
                    "regions": ["us-east-1"],
                    "categories": ["storage"],
                    "cost_start_month": "2026-10",
                    "cost_end_month": "2026-11",
                },
                cost_rows=[],
                scan_warnings=[],
                cost_warnings=["Cost Explorer permission denied."],
            )

            self.assertTrue(zipfile.is_zipfile(output_path))
            with zipfile.ZipFile(output_path) as archive:
                resource_headers, resource_range, _ = table_columns(
                    archive, "InventoryTable"
                )
                self.assertEqual(resource_range, "A1:N2")
                self.assertEqual(resource_headers[0], "Profile")
                warning_headers, warning_range, _ = table_columns(
                    archive, "WarningsTable"
                )
                self.assertEqual(warning_headers[-1], "說明")
                self.assertEqual(warning_range, "A22:G25")
                self.assertIn(
                    "Cost Explorer permission denied.",
                    shared_strings(archive),
                )
                self.assertIn(
                    "Inventory scanner returned a non-zero exit code.",
                    shared_strings(archive),
                )


if __name__ == "__main__":
    unittest.main()
