"""Build the human-readable AWS inventory and cost workbook."""

import json
import re
from collections import Counter, defaultdict
from decimal import Decimal, InvalidOperation
from pathlib import Path

import xlsxwriter


CATEGORY_LABELS = {
    "billing": "可能產生成本",
    "storage": "儲存",
    "compute": "運算",
    "security": "安全",
}

CATEGORY_COLORS = {
    "可能產生成本": "#FFF2CC",
    "儲存": "#E2F0D9",
    "運算": "#DDEBF7",
    "安全": "#E4DFEC",
}

GLOBAL_SERVICES = {"iam", "s3"}

RESOURCE_HEADERS = [
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
]

COST_HEADERS = [
    "費用月份",
    "AWS 帳號 ID",
    "帳號名稱",
    "服務",
    "Region",
    "費用金額",
    "幣別",
    "是否為估算",
]

WARNING_HEADERS = [
    "來源",
    "Profile",
    "AWS 帳號 ID",
    "Region",
    "類別／服務",
    "狀態",
    "說明",
]

RESOURCE_TYPE_LABELS = {
    ("cloudformation", "list_stacks"): "CloudFormation Stack",
    ("ec2", "describe_addresses"): "Elastic IP",
    ("ec2", "describe_instances"): "EC2 Instance",
    ("ec2", "describe_nat_gateways"): "NAT Gateway",
    ("ec2", "describe_snapshots"): "EBS Snapshot",
    ("ec2", "describe_volumes"): "EBS Volume",
    ("ec2", "describe_vpn_gateways"): "VPN Gateway",
    ("eks", "list_clusters"): "EKS Cluster",
    ("elbv2", "describe_load_balancers"): "Load Balancer",
    ("iam", "list_access_keys"): "IAM Access Key",
    ("iam", "list_roles"): "IAM Role",
    ("iam", "list_users"): "IAM User",
    ("iam", "list_virtual_mfa_devices"): "Virtual MFA Device",
    ("lambda", "list_functions"): "Lambda Function",
    ("rds", "describe_db_clusters"): "RDS Cluster",
    ("rds", "describe_db_instances"): "RDS Instance",
    ("s3", "list_buckets"): "S3 Bucket",
}

SERVICE_LABELS = {
    "cloudformation": "CloudFormation",
    "ec2": "EC2",
    "eks": "EKS",
    "elbv2": "ELBv2",
    "iam": "IAM",
    "lambda": "Lambda",
    "rds": "RDS",
    "s3": "S3",
}

RESOURCE_ID_KEYS = (
    "InstanceId",
    "VolumeId",
    "SnapshotId",
    "AllocationId",
    "NatGatewayId",
    "VpnGatewayId",
    "LoadBalancerArn",
    "DBInstanceIdentifier",
    "DBClusterIdentifier",
    "FunctionName",
    "StackId",
    "StackName",
    "ClusterName",
    "BucketName",
    "UserId",
    "RoleId",
    "AccessKeyId",
    "SerialNumber",
    "RoleName",
    "UserName",
    "FunctionArn",
    "DBInstanceArn",
    "DBClusterArn",
    "ClusterArn",
    "BucketArn",
    "Arn",
    "ARN",
    "Id",
)

RESOURCE_NAME_KEYS = (
    "Name",
    "BucketName",
    "DBInstanceIdentifier",
    "DBClusterIdentifier",
    "LoadBalancerName",
    "FunctionName",
    "StackName",
    "ClusterName",
    "UserName",
    "RoleName",
    "KeyName",
)

CREATED_KEYS = (
    "CreationDate",
    "CreateTime",
    "CreateDate",
    "LaunchTime",
    "LastModified",
    "LastModifiedTime",
    "StartTime",
)


def _load_scan_definitions(scans_dir):
    definitions = {}
    for path in Path(scans_dir).glob("*.json"):
        try:
            entries = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for entry in entries:
            service = entry.get("service")
            function = entry.get("function")
            if service and function:
                definitions["{}-{}".format(service, function)] = (service, function)
    return definitions


def _json_value(value):
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, default=str)
    return str(value)


def _resource_items(payload, service, function):
    if isinstance(payload, list):
        if service == "ec2" and function == "describe_instances":
            instances = []
            for reservation in payload:
                if isinstance(reservation, dict):
                    for instance in reservation.get("Instances", []):
                        if isinstance(instance, dict):
                            instances.append(instance)
            return instances

        return [
            item if isinstance(item, dict) else {"Name": _json_value(item)}
            for item in payload
        ]

    if isinstance(payload, dict):
        return [payload]

    return []


def _get_nested(item, *path):
    current = item
    for key in path:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def _tags_text(tags):
    if isinstance(tags, dict):
        pairs = tags.items()
    elif isinstance(tags, list):
        pairs = (
            (tag.get("Key"), tag.get("Value"))
            for tag in tags
            if isinstance(tag, dict)
        )
    else:
        return ""

    return "; ".join(
        "{}={}".format(key, value)
        for key, value in pairs
        if key is not None and value is not None
    )


def _resource_name(item):
    for key in RESOURCE_NAME_KEYS:
        value = item.get(key)
        if value:
            return _json_value(value)

    for key in ("User", "Cluster"):
        value = item.get(key)
        if isinstance(value, dict):
            nested_name = value.get("UserName") or value.get("Name")
            if nested_name:
                return _json_value(nested_name)

    for tag in item.get("Tags", []) if isinstance(item.get("Tags"), list) else []:
        if isinstance(tag, dict) and tag.get("Key") == "Name":
            return _json_value(tag.get("Value"))
    return ""


def _resource_id(item, name, arn):
    for key in RESOURCE_ID_KEYS:
        value = item.get(key)
        if value:
            return _json_value(value)
    return arn or name


def _resource_state(item):
    for key in (
        "State",
        "Status",
        "DBInstanceStatus",
        "DBClusterStatus",
        "StackStatus",
    ):
        value = item.get(key)
        if isinstance(value, dict):
            value = value.get("Name") or value.get("Code")
        if value is not None:
            return _json_value(value)
    return ""


def _created_at(item):
    for key in CREATED_KEYS:
        value = item.get(key)
        if value:
            return _json_value(value)
    return ""


def _main_info(service, function, item):
    fields = []
    field_specs = {
        ("ec2", "describe_instances"): [
            ("InstanceType", "Type"),
            ("State", "State", "Name"),
            ("Placement", "AZ", "AvailabilityZone"),
            ("VpcId", "VPC"),
            ("PrivateIpAddress", "Private IP"),
            ("PublicIpAddress", "Public IP"),
        ],
        ("ec2", "describe_volumes"): [
            ("VolumeType", "Type"),
            ("Size", "Size (GiB)"),
            ("State", "State"),
            ("AvailabilityZone", "AZ"),
        ],
        ("ec2", "describe_snapshots"): [
            ("VolumeSize", "Size (GiB)"),
            ("State", "State"),
            ("StartTime", "Started"),
        ],
        ("ec2", "describe_addresses"): [
            ("PublicIp", "Public IP"),
            ("InstanceId", "Instance"),
            ("NetworkInterfaceId", "Interface"),
        ],
        ("ec2", "describe_nat_gateways"): [
            ("State", "State"),
            ("SubnetId", "Subnet"),
            ("VpcId", "VPC"),
            ("ConnectivityType", "Connectivity"),
        ],
        ("ec2", "describe_vpn_gateways"): [
            ("State", "State"),
            ("Type", "Type"),
            ("VpcId", "VPC"),
        ],
        ("elbv2", "describe_load_balancers"): [
            ("Type", "Type"),
            ("Scheme", "Scheme"),
            ("VpcId", "VPC"),
            ("State", "State", "Code"),
        ],
        ("rds", "describe_db_instances"): [
            ("Engine", "Engine"),
            ("EngineVersion", "Version"),
            ("DBInstanceClass", "Class"),
            ("DBInstanceStatus", "Status"),
            ("MultiAZ", "Multi-AZ"),
        ],
        ("rds", "describe_db_clusters"): [
            ("Engine", "Engine"),
            ("EngineVersion", "Version"),
            ("DBClusterStatus", "Status"),
            ("Endpoint", "Endpoint"),
        ],
        ("lambda", "list_functions"): [
            ("Runtime", "Runtime"),
            ("MemorySize", "Memory (MiB)"),
            ("Timeout", "Timeout (s)"),
            ("LastModified", "Modified"),
        ],
        ("cloudformation", "list_stacks"): [
            ("StackStatus", "Status"),
            ("CreationTime", "Created"),
        ],
        ("iam", "list_access_keys"): [
            ("UserName", "User"),
            ("Status", "Status"),
            ("CreateDate", "Created"),
        ],
        ("iam", "list_virtual_mfa_devices"): [
            ("User", "User", "UserName"),
            ("SerialNumber", "Serial"),
            ("EnableDate", "Enabled"),
        ],
    }
    for spec in field_specs.get((service, function), []):
        *path, label = spec
        value = _get_nested(item, *path)
        if value is not None and value != "":
            fields.append("{}: {}".format(label, _json_value(value)))
    return " | ".join(fields)


def _resource_type(service, function):
    return RESOURCE_TYPE_LABELS.get(
        (service, function), function.replace("_", " ").title()
    )


def _resource_rows(run_dir, scans_dir, account_profiles):
    definitions = _load_scan_definitions(scans_dir)
    rows = []
    global_seen = set()

    for path in sorted(Path(run_dir).glob("*/*/*/*/*.json")):
        relative = path.relative_to(run_dir)
        if len(relative.parts) < 5:
            continue
        account_id, category, _, region = relative.parts[:4]
        service_function = path.stem
        service_function_pair = definitions.get(service_function)
        if not service_function_pair:
            continue
        service, function = service_function_pair

        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue

        for item in _resource_items(payload, service, function):
            name = _resource_name(item)
            arn = _json_value(
                item.get("Arn")
                or item.get("ARN")
                or item.get("BucketArn")
                or item.get("LoadBalancerArn")
                or item.get("DBInstanceArn")
                or item.get("DBClusterArn")
                or item.get("FunctionArn")
                or item.get("ClusterArn")
                or item.get("StackId")
                or ""
            )
            resource_id = _resource_id(item, name, arn)
            resource_type = _resource_type(service, function)
            display_region = region

            if service in GLOBAL_SERVICES:
                identity = resource_id or name or json.dumps(item, sort_keys=True)
                key = (account_id, service, resource_type, identity)
                if key in global_seen:
                    continue
                global_seen.add(key)
                display_region = "Global"

            row = [
                "; ".join(account_profiles.get(account_id, [])),
                account_id,
                CATEGORY_LABELS.get(category, category),
                SERVICE_LABELS.get(service, service),
                resource_type,
                name,
                resource_id,
                display_region,
                _resource_state(item),
                _created_at(item),
                arn,
                _tags_text(item.get("Tags")),
                _main_info(service, function, item),
                path.relative_to(run_dir).as_posix(),
            ]
            rows.append((row, path))

    rows.sort(
        key=lambda item: (
            item[0][1],
            item[0][2],
            item[0][3],
            item[0][7],
            item[0][5],
            item[0][6],
        )
    )
    return rows


def _parse_scan_warnings(run_dir, account_profiles):
    warnings = []
    warning_file = Path(run_dir) / "scan-errors.tsv"
    if warning_file.exists():
        for line in warning_file.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            fields = line.split("\t", 4)
            fields += [""] * (5 - len(fields))
            profile, account_id, category, status, description = fields[:5]
            warnings.append(
                [
                    "資源掃描",
                    profile,
                    account_id,
                    "",
                    category,
                    status or "失敗",
                    description,
                ]
            )

    error_pattern = re.compile(
        r"Error while processing\s+([^,]+),\s*([^\s.]+)"
    )
    for log_path in sorted(Path(run_dir).glob("*/*/aws_resources_*.log")):
        relative = log_path.relative_to(run_dir)
        account_id, category = relative.parts[:2]
        profile = "; ".join(account_profiles.get(account_id, []))
        try:
            lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            if " - ERROR - " not in line:
                continue
            message = line.split(" - ERROR - ", 1)[-1].strip()
            match = error_pattern.search(message)
            service = ""
            region = ""
            if match:
                service, region = match.groups()
            warnings.append(
                [
                    "資源掃描",
                    profile,
                    account_id,
                    region,
                    "{} / {}".format(category, service).strip(" /"),
                    "失敗",
                    message[:500],
                ]
            )
    return warnings


def _normalize_warning(warning):
    if isinstance(warning, dict):
        return [
            warning.get("source", "掃描"),
            warning.get("profile", ""),
            warning.get("account_id", ""),
            warning.get("region", ""),
            warning.get("item", ""),
            warning.get("status", "警告"),
            str(warning.get("message", ""))[:500],
        ]
    return ["Cost Explorer", "", "", "", "", "警告", str(warning)[:500]]


def _write_table(worksheet, row, col, name, headers, data):
    # XlsxWriter requires one data row for a table. A blank row keeps the
    # filter controls available when a scan or cost query returned no rows.
    table_data = data or [[None] * len(headers)]
    last_row = row + len(table_data)
    last_col = col + len(headers) - 1
    worksheet.add_table(
        row,
        col,
        last_row,
        last_col,
        {
            "name": name,
            "style": "Table Style Light 1",
            "columns": [{"header": header} for header in headers],
            "data": table_data,
        },
    )
    return row + 1, last_row


def _format_account_rows(profiles, regions, resource_rows, warning_rows):
    account_profiles = defaultdict(list)
    for entry in profiles:
        account_id = entry.get("account_id", "")
        profile = entry.get("profile", "")
        if account_id and profile and profile not in account_profiles[account_id]:
            account_profiles[account_id].append(profile)

    resource_counts = Counter(row[1] for row, _ in resource_rows)
    account_warnings = {
        warning[2]
        for warning in warning_rows
        if warning[2]
    }
    account_ids = sorted(set(account_profiles) | set(resource_counts))
    return [
        [
            "; ".join(account_profiles.get(account_id, [])),
            account_id,
            ", ".join(regions),
            resource_counts.get(account_id, 0),
            "有警告" if account_id in account_warnings else "未偵測到錯誤",
        ]
        for account_id in account_ids
    ]


def _format_cost_rows(cost_rows):
    rows = []
    for cost in cost_rows:
        rows.append(
            [
                cost.get("month", ""),
                cost.get("account_id", ""),
                cost.get("account_name", ""),
                cost.get("service", ""),
                cost.get("region", ""),
                float(Decimal(str(cost.get("amount", "0")))),
                cost.get("unit", ""),
                "是" if cost.get("estimated") else "否",
            ]
        )
    return rows


def _cost_summary_rows(cost_rows):
    totals = defaultdict(Decimal)
    estimated = defaultdict(bool)
    for cost in cost_rows:
        key = (cost.get("month", ""), cost.get("unit", ""))
        try:
            totals[key] += Decimal(str(cost.get("amount", "0")))
        except (InvalidOperation, TypeError):
            continue
        estimated[key] = estimated[key] or bool(cost.get("estimated"))
    return [
        [month, float(amount), unit, "是" if estimated[(month, unit)] else "否"]
        for (month, unit), amount in sorted(totals.items())
    ]


def create_workbook(
    run_dir,
    output_path,
    metadata,
    cost_rows,
    scan_warnings=None,
    cost_warnings=None,
    scans_dir=None,
):
    """Create a formatted workbook from one scan run and its cost query."""
    run_dir = Path(run_dir)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    scans_dir = scans_dir or Path(__file__).parent / "scans"
    scan_warnings = scan_warnings or []
    cost_warnings = cost_warnings or []

    profile_entries = metadata.get("profiles", [])
    account_profiles = defaultdict(list)
    for entry in profile_entries:
        account_id = entry.get("account_id", "")
        profile = entry.get("profile", "")
        if account_id and profile and profile not in account_profiles[account_id]:
            account_profiles[account_id].append(profile)

    resource_rows = _resource_rows(run_dir, scans_dir, account_profiles)
    warning_rows = _parse_scan_warnings(run_dir, account_profiles)
    warning_rows.extend(_normalize_warning(item) for item in scan_warnings)
    warning_rows.extend(_normalize_warning(item) for item in cost_warnings)

    category_counts = Counter(row[2] for row, _ in resource_rows)
    selected_categories = metadata.get("categories", [])
    category_rows = [
        [
            CATEGORY_LABELS.get(category, category),
            category_counts.get(CATEGORY_LABELS.get(category, category), 0),
        ]
        for category in selected_categories
    ]
    account_rows = _format_account_rows(
        profile_entries,
        metadata.get("regions", []),
        resource_rows,
        warning_rows,
    )
    cost_data = _format_cost_rows(cost_rows)
    cost_summary = _cost_summary_rows(cost_rows)

    workbook = xlsxwriter.Workbook(
        str(output_path),
        {
            "strings_to_formulas": False,
            "strings_to_urls": False,
        },
    )
    workbook.set_properties(
        {
            "title": "AWS 資源與費用報表",
            "subject": "AWS account inventory",
            "author": "AWS Account Inventory Scanner",
        }
    )

    title_format = workbook.add_format(
        {"bold": True, "font_size": 18, "font_color": "#17365D"}
    )
    label_format = workbook.add_format(
        {"bold": True, "font_color": "#404040", "bg_color": "#F2F2F2"}
    )
    value_format = workbook.add_format({"text_wrap": True, "valign": "top"})
    money_format = workbook.add_format({"num_format": "#,##0.00"})
    wrapped_format = workbook.add_format({"text_wrap": True, "valign": "top"})

    overview = workbook.add_worksheet("總覽")
    overview.set_tab_color("#4472C4")
    overview.set_column("A:A", 24)
    overview.set_column("B:B", 34)
    overview.set_column("C:H", 20)
    overview.freeze_panes(1, 0)
    overview.write("A1", "AWS 資源與費用報表", title_format)

    profiles_text = ", ".join(
        entry.get("profile", "") for entry in profile_entries if entry.get("profile")
    )
    account_ids_text = ", ".join(
        sorted(
            {
                entry.get("account_id", "")
                for entry in profile_entries
                if entry.get("account_id")
            }
        )
    )
    metadata_rows = [
        ("報表產生時間", metadata.get("generated_at", "")),
        ("掃描時間戳", metadata.get("run_timestamp", "")),
        ("掃描 Profiles", profiles_text),
        ("AWS 帳號 ID", account_ids_text),
        ("Cost Explorer Management Account ID", metadata.get("cost_account_id", "")),
        ("掃描 Regions", ", ".join(metadata.get("regions", []))),
        (
            "資源類別",
            ", ".join(
                CATEGORY_LABELS.get(category, category)
                for category in metadata.get("categories", [])
            ),
        ),
        (
            "費用查詢期間",
            "{} 至 {}".format(
                metadata.get("cost_start_month", ""),
                metadata.get("cost_end_month", ""),
            ),
        ),
        ("費用查詢 Profile", metadata.get("cost_profile", "")),
        ("資源總數", len(resource_rows)),
    ]
    for row_index, (label, value) in enumerate(metadata_rows, start=2):
        overview.write(row_index, 0, label, label_format)
        overview.write(row_index, 1, value, value_format)

    account_start = 13
    overview.write(account_start - 1, 0, "帳號摘要", label_format)
    _write_table(
        overview,
        account_start,
        0,
        "AccountSummaryTable",
        ["Profile", "AWS 帳號 ID", "掃描 Regions", "資源數", "掃描狀態"],
        account_rows,
    )

    category_start = 13
    overview.write(category_start - 1, 6, "類別摘要", label_format)
    _write_table(
        overview,
        category_start,
        6,
        "CategorySummaryTable",
        ["資源類別", "資源數"],
        category_rows,
    )

    cost_summary_start = 13 + max(len(account_rows), len(category_rows)) + 3
    overview.write(cost_summary_start - 1, 0, "每月費用摘要", label_format)
    _write_table(
        overview,
        cost_summary_start,
        0,
        "MonthlyCostSummaryTable",
        ["費用月份", "費用金額", "幣別", "是否為估算"],
        cost_summary,
    )
    for row_index in range(cost_summary_start + 1, cost_summary_start + 1 + len(cost_summary)):
        overview.write_number(row_index, 1, cost_summary[row_index - cost_summary_start - 1][1], money_format)

    warning_start = cost_summary_start + len(cost_summary) + 4
    overview.write(warning_start - 1, 0, "掃描與費用警告", label_format)
    _write_table(
        overview,
        warning_start,
        0,
        "WarningsTable",
        WARNING_HEADERS,
        warning_rows,
    )
    overview.set_column("G:G", 46, wrapped_format)

    inventory = workbook.add_worksheet("資源清單")
    inventory.set_tab_color("#70AD47")
    inventory.freeze_panes(1, 2)
    inventory.set_column("A:B", 20)
    inventory.set_column("C:E", 18)
    inventory.set_column("F:G", 28)
    inventory.set_column("H:I", 18)
    inventory.set_column("J:J", 26)
    inventory.set_column("K:K", 42)
    inventory.set_column("L:L", 32)
    inventory.set_column("M:M", 60, wrapped_format)
    inventory.set_column("N:N", 26)
    inventory_data = [row for row, _ in resource_rows]
    inventory_start, inventory_last = _write_table(
        inventory,
        0,
        0,
        "InventoryTable",
        RESOURCE_HEADERS,
        inventory_data,
    )
    if inventory_data:
        for offset, (_, source_path) in enumerate(resource_rows):
            relative_path = source_path.relative_to(run_dir).as_posix()
            inventory.write_url(
                inventory_start + offset,
                len(RESOURCE_HEADERS) - 1,
                "external:" + relative_path,
                string=source_path.name,
                tip=relative_path,
            )

        category_column = RESOURCE_HEADERS.index("資源類別")
        for category, color in CATEGORY_COLORS.items():
            inventory.conditional_format(
                1,
                0,
                inventory_last,
                len(RESOURCE_HEADERS) - 1,
                {
                    "type": "formula",
                    "criteria": '=${}2="{}"'.format(
                        xlsxwriter.utility.xl_col_to_name(category_column), category
                    ),
                    "format": workbook.add_format({"bg_color": color}),
                },
            )

    costs_sheet = workbook.add_worksheet("費用明細")
    costs_sheet.set_tab_color("#ED7D31")
    costs_sheet.freeze_panes(1, 2)
    costs_sheet.set_column("A:A", 14)
    costs_sheet.set_column("B:B", 18)
    costs_sheet.set_column("C:D", 34)
    costs_sheet.set_column("E:E", 20)
    costs_sheet.set_column("F:F", 18, money_format)
    costs_sheet.set_column("G:H", 16)
    _write_table(costs_sheet, 0, 0, "CostsTable", COST_HEADERS, cost_data)

    workbook.close()
    return output_path
