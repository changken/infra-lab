import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from generate_report import generate_report


class GenerateReportTests(unittest.TestCase):
    @patch("generate_report.create_workbook")
    @patch("generate_report.query_costs")
    @patch("generate_report.boto3.Session")
    def test_cost_explorer_is_not_called_by_default(
        self, session_factory, query_costs, create_workbook
    ):
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = generate_report(
                run_dir=Path(temp_dir) / "inventory-output" / "run",
                run_timestamp="20261125T120000",
                profile_accounts=[],
                regions=["us-east-1"],
                categories=["security"],
            )

        session_factory.assert_not_called()
        query_costs.assert_not_called()
        metadata = create_workbook.call_args.kwargs["metadata"]
        self.assertFalse(metadata["cost_query_enabled"])
        self.assertEqual(create_workbook.call_args.kwargs["cost_rows"], [])
        self.assertEqual(
            output_path.name,
            "aws-report-2026-11-25-12-00-00.xlsx",
        )


if __name__ == "__main__":
    unittest.main()
