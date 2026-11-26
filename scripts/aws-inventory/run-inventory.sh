#!/usr/bin/env bash
# =============================================================================
# run-inventory.sh
# AWS 跨帳號資源盤點 — 編排層
# 底層掃描引擎：aws-auto-inventory/scan.py
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="${SCRIPT_DIR}/vendor/aws-auto-inventory"
SCAN_PY="${VENDOR_DIR}/scan.py"
REPORT_PY="${SCRIPT_DIR}/generate_report.py"
IAM_ACCESS_KEYS_PY="${SCRIPT_DIR}/iam_access_keys.py"
PYTHON="${VENDOR_DIR}/.venv/bin/python3"
SCANS_DIR="${SCRIPT_DIR}/scans"
OUTPUT_BASE="${SCRIPT_DIR}/inventory-output"
declare -A PROFILE_ACCOUNT_IDS=()
COST_PROFILE=""
COST_ACCOUNT_ID=""
COST_START_MONTH=""
COST_END_MONTH=""
COST_QUERY_ENABLED=false

# -----------------------------------------------------------------------------
# 顏色
# -----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

# -----------------------------------------------------------------------------
# 互動式多選選單
# multiselect <result_var> <options_array_name> <defaults_array_name>
# -----------------------------------------------------------------------------
multiselect() {
  set +e
  local result_var="$1"
  local -n _opts="$2"
  local -n _defs="$3"

  local _sel=()
  for _o in "${_opts[@]}"; do
    local _found=false
    for _d in "${_defs[@]}"; do
      if [[ "$_o" == "$_d" ]]; then _found=true; break; fi
    done
    if [[ "$_found" == "true" ]]; then _sel+=("true"); else _sel+=("false"); fi
  done

  local _cur=0
  local _total=${#_opts[@]}
  tput civis 2>/dev/null || true

  _ms_draw() {
    tput cup $(($(tput lines) - _total - 3)) 0 2>/dev/null || true
    echo "  （↑↓ 移動，空白切換，Enter 確認）"
    echo ""
    for _i in "${!_opts[@]}"; do
      local _m="[ ]"
      [[ "${_sel[$_i]}" == "true" ]] && _m="[x]"
      if [[ $_i -eq $_cur ]]; then
        echo -e "  ${CYAN}▶ ${_m} ${_opts[$_i]}${NC}"
      else
        echo "    ${_m} ${_opts[$_i]}"
      fi
    done
  }

  for _ in $(seq 1 $((_total + 3))); do echo ""; done

  local _k _k2
  while true; do
    _ms_draw
    IFS= read -rsn1 _k < /dev/tty
    if [[ "$_k" == $'\x1b' ]]; then
      read -rsn2 -t 0.1 _k2 < /dev/tty || true
      _k="${_k}${_k2}"
    fi
    case "$_k" in
      $'\x1b[A') [[ $_cur -gt 0 ]] && ((_cur--)) ;;
      $'\x1b[B') [[ $_cur -lt $((_total-1)) ]] && ((_cur++)) ;;
      ' ')
        if [[ "${_sel[$_cur]}" == "true" ]]; then
          _sel[$_cur]="false"
        else
          _sel[$_cur]="true"
        fi
        ;;
      '') break ;;
    esac
  done

  tput cnorm 2>/dev/null || true
  local _res=()
  for _j in "${!_opts[@]}"; do
    [[ "${_sel[$_j]}" == "true" ]] && _res+=("${_opts[$_j]}")
  done
  eval "${result_var}=(\"\${_res[@]}\")"
  set -e
}

# -----------------------------------------------------------------------------
# 前置檢查
# -----------------------------------------------------------------------------
preflight() {
  if [[ ! -f "$SCAN_PY" ]]; then
    error "找不到 ${SCAN_PY}"
    error "請先執行: git submodule update --init"
    exit 1
  fi
  if [[ ! -f "$PYTHON" ]]; then
    error "找不到 venv，請先執行:"
    error "  cd vendor/aws-auto-inventory && python3 -m venv .venv && .venv/bin/pip install boto3 requests jq XlsxWriter"
    exit 1
  fi
  if [[ ! -f "$REPORT_PY" ]]; then
    error "找不到 ${REPORT_PY}"
    exit 1
  fi
  if [[ ! -f "$IAM_ACCESS_KEYS_PY" ]]; then
    error "找不到 ${IAM_ACCESS_KEYS_PY}"
    exit 1
  fi
  if ! "${PYTHON}" -c 'import boto3, xlsxwriter' &>/dev/null; then
    error "Python venv 缺少 boto3 或 XlsxWriter，請先執行:"
    error "  cd vendor/aws-auto-inventory && .venv/bin/pip install boto3 requests jq XlsxWriter"
    exit 1
  fi
  if ! aws --version &>/dev/null; then
    error "找不到 aws CLI"
    exit 1
  fi
}

ensure_sso_login() {
  local profile="$1"
  if aws sts get-caller-identity --profile "${profile}" &>/dev/null; then
    return 0
  fi

  warn "Profile ${profile} 的 SSO token 無效或已過期，嘗試重新登入..."
  if ! aws sso login --profile "${profile}"; then
    return 1
  fi
  aws sts get-caller-identity --profile "${profile}" &>/dev/null
}

# -----------------------------------------------------------------------------
# 步驟 1：選擇 Profiles
# -----------------------------------------------------------------------------
select_profiles() {
  header "步驟 1/5：選擇要掃描的 AWS Profiles"
  info "讀取 ~/.aws/config ..."

  mapfile -t ALL_PROFILES < <(aws configure list-profiles 2>/dev/null | grep -v '^default$' | sort)
  if [[ ${#ALL_PROFILES[@]} -eq 0 ]]; then
    error "找不到任何 named profile"
    exit 1
  fi

  local _empty=()
  multiselect SELECTED_PROFILES ALL_PROFILES _empty
  if [[ ${#SELECTED_PROFILES[@]} -eq 0 ]]; then
    error "未選擇任何 profile"
    exit 1
  fi
  success "已選 ${#SELECTED_PROFILES[@]} 個 profile：${SELECTED_PROFILES[*]}"
}

# -----------------------------------------------------------------------------
# 選擇管理帳號 Profile，供 Cost Explorer 查詢整個 Organization
# -----------------------------------------------------------------------------
select_cost_profile() {
  header "選擇 Cost Explorer 使用的 Management Account Profile"
  echo "  （這是 SSO Profile，不是 root 身分）"
  local _i=1
  local _profile
  for _profile in "${ALL_PROFILES[@]}"; do
    printf "  %d) %s\n" "${_i}" "${_profile}"
    _i=$((_i + 1))
  done

  local _choice
  while true; do
    read -rp "輸入 Profile 編號: " _choice < /dev/tty
    if [[ "$_choice" =~ ^[0-9]+$ ]] &&
      (( _choice >= 1 && _choice <= ${#ALL_PROFILES[@]} )); then
      COST_PROFILE="${ALL_PROFILES[$((_choice - 1))]}"
      break
    fi
    warn "請輸入有效的編號。"
  done

  info "Cost Explorer Profile: ${COST_PROFILE}"
}

authenticate_cost_profile() {
  if ! ensure_sso_login "${COST_PROFILE}"; then
    warn "無法驗證 Profile ${COST_PROFILE}；報表仍會產生並記錄費用查詢警告。"
    return 1
  fi

  COST_ACCOUNT_ID=$(aws sts get-caller-identity --profile "${COST_PROFILE}" \
    --query 'Account' --output text 2>/dev/null || true)
  [[ "$COST_ACCOUNT_ID" == "None" ]] && COST_ACCOUNT_ID=""
  if [[ -n "$COST_ACCOUNT_ID" ]]; then
    info "Cost Explorer Account ID: ${COST_ACCOUNT_ID}"
  else
    warn "無法取得 Cost Explorer Profile 的 Account ID；報表仍會產生。"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# 選擇 Cost Explorer 費用查詢月份
# -----------------------------------------------------------------------------
select_cost_period() {
  header "輸入 Cost Explorer 費用查詢月份"
  local _default_start
  local _default_end
  local _current_month
  _default_end=$(date +"%Y-%m")
  _default_start=$(date -d "${_default_end}-01 -1 month" +"%Y-%m")
  _current_month="${_default_end}"

  while true; do
    local _start _end _start_valid _end_valid _range_valid
    read -rp "起始月份 [${_default_start}]: " _start < /dev/tty
    read -rp "結束月份 [${_default_end}]: " _end < /dev/tty
    _start="${_start:-${_default_start}}"
    _end="${_end:-${_default_end}}"

    _start_valid=$(date -d "${_start}-01" +"%Y-%m" 2>/dev/null || true)
    _end_valid=$(date -d "${_end}-01" +"%Y-%m" 2>/dev/null || true)
    _range_valid=false
    if [[ "$_start" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ &&
          "$_end" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ &&
          "$_start_valid" == "$_start" &&
          "$_end_valid" == "$_end" ]]; then
      if [[ "$_start" == "$_end" || "$_start" < "$_end" ]] &&
        [[ "$_end" == "$_current_month" || "$_end" < "$_current_month" ]]; then
        _range_valid=true
      fi
    fi
    if [[ "$_range_valid" == "true" ]]; then
      COST_START_MONTH="$_start"
      COST_END_MONTH="$_end"
      break
    fi
    warn "月份請使用 YYYY-MM；起始月份不得晚於結束月份，且結束月份不能在未來。"
  done
  success "費用期間：${COST_START_MONTH} 至 ${COST_END_MONTH}"
}

select_cost_query() {
  header "可選：Cost Explorer 費用查詢"
  warn 'AWS 帳單顯示每次 API request 為 USD 0.01；逐 Region 查詢及分頁會增加請求數。'
  local _answer
  read -rp "本次要查詢費用嗎？(y/N，預設不查) " _answer < /dev/tty
  if [[ ! "$_answer" =~ ^[Yy]$ ]]; then
    info "略過 Cost Explorer；本次不會送出 Cost Explorer API request。"
    return 0
  fi

  COST_QUERY_ENABLED=true
  select_cost_profile
  select_cost_period
}

# -----------------------------------------------------------------------------
# 步驟 2：選擇 Regions
# -----------------------------------------------------------------------------
select_regions() {
  header "步驟 2/5：選擇要掃描的 Regions"

  local ALL_REGIONS=(
    "us-east-1" "us-east-2" "us-west-1" "us-west-2"
    "ap-northeast-1" "ap-northeast-2" "ap-northeast-3"
    "ap-east-1" "ap-southeast-1" "ap-southeast-2" "ap-south-1"
    "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "eu-north-1"
    "ca-central-1" "sa-east-1" "me-south-1" "af-south-1"
  )
  local DEFAULT_REGIONS=("us-east-1" "us-west-2" "ap-northeast-1" "ap-east-1")

  multiselect SELECTED_REGIONS ALL_REGIONS DEFAULT_REGIONS
  if [[ ${#SELECTED_REGIONS[@]} -eq 0 ]]; then
    error "未選擇任何 Region"
    exit 1
  fi
  success "已選 ${#SELECTED_REGIONS[@]} 個 Region：${SELECTED_REGIONS[*]}"
}

# -----------------------------------------------------------------------------
# 步驟 3：選擇資源類別
# -----------------------------------------------------------------------------
select_categories() {
  header "步驟 3/5：選擇要掃描的資源類別"
  echo "  （各類別對應 scans/ 目錄下的 JSON scan file）"

  local ALL_CATS=("billing" "storage" "compute" "security")
  local DEFAULT_CATS=("billing" "storage" "compute" "security")

  multiselect SELECTED_CATS ALL_CATS DEFAULT_CATS
  if [[ ${#SELECTED_CATS[@]} -eq 0 ]]; then
    error "未選擇任何類別"
    exit 1
  fi
  success "已選類別：${SELECTED_CATS[*]}"
}

# -----------------------------------------------------------------------------
# 掃描
# -----------------------------------------------------------------------------
run_scan() {
  local profile="$1"
  local account_id="$2"
  local run_ts="$3"

  local out_dir="${OUTPUT_BASE}/${run_ts}/${account_id}"
  local status_file="${OUTPUT_BASE}/${run_ts}/scan-errors.tsv"
  mkdir -p "${out_dir}"

  for cat in "${SELECTED_CATS[@]}"; do
    local scan_file="${SCANS_DIR}/${cat}.json"
    local scan_regions=("${SELECTED_REGIONS[@]}")
    if [[ ! -f "$scan_file" ]]; then
      warn "找不到 ${scan_file}，跳過"
      printf "%s\t%s\t%s\t%s\t%s\n" \
        "${profile}" "${account_id}" "${cat}" "設定缺失" \
        "Scan definition not found: ${scan_file}" >> "${status_file}"
      continue
    fi

    if [[ "$cat" == "security" ]]; then
      # IAM is global; scanning it once avoids redundant calls for every Region.
      scan_regions=("us-east-1")
    fi

    info "  掃描類別 [${cat}] ..."
    if ! AWS_PROFILE="${profile}" "${PYTHON}" "${SCAN_PY}" \
      --scan "${scan_file}" \
      --regions "${scan_regions[@]}" \
      --output_dir "${out_dir}/${cat}" \
      --log_level WARNING \
      2>&1; then
      printf "%s\t%s\t%s\t%s\t%s\n" \
        "${profile}" "${account_id}" "${cat}" "執行失敗" \
        "Inventory scanner returned a non-zero exit code." >> "${status_file}"
    fi
  done

  if [[ " ${SELECTED_CATS[*]} " == *" security "* ]]; then
    info "  掃描 IAM 使用者 Access Keys ..."
    if ! "${PYTHON}" "${IAM_ACCESS_KEYS_PY}" \
      --profile "${profile}" \
      --output-dir "${out_dir}/security" \
      2>&1; then
      printf "%s\t%s\t%s\t%s\t%s\n" \
        "${profile}" "${account_id}" "security" "IAM Access Key 掃描警告" \
        "See console output for users whose access keys could not be queried." \
        >> "${status_file}"
    fi
  fi
}

# -----------------------------------------------------------------------------
# 輸出摘要
# -----------------------------------------------------------------------------
print_summary() {
  local run_ts="$1"
  local out_base="${OUTPUT_BASE}/${run_ts}"

  echo ""
  header "掃描結果摘要"
  info "輸出目錄：${out_base}"
  echo ""

  local found_any=false

  for acct_dir in "${out_base}"/*/; do
    [[ -d "$acct_dir" ]] || continue
    local acct="${acct_dir%/}"
    acct="${acct##*/}"
    echo -e "  ${BOLD}Account: ${acct}${NC}"

    local acct_has_data=false
    while IFS= read -r f; do
      local rel="${f#${acct_dir}}"
      local count
      count=$("${PYTHON}" -c "
import json
try:
    d = json.load(open('$f'))
    if isinstance(d, list): print(len(d))
    elif isinstance(d, dict):
        vals = [v for v in d.values() if isinstance(v, list)]
        print(sum(len(v) for v in vals) if vals else 1)
    else: print(1)
except: print(0)
" 2>/dev/null || echo "0")
      if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
        echo -e "    ${GREEN}✔ ${count} 筆${NC}  ${rel}"
        acct_has_data=true
        found_any=true
      fi
    done < <(find "${acct_dir}" -name "*.json" | sort)

    if [[ "$acct_has_data" == "false" ]]; then
      if grep -rqlE " - ERROR - |AccessDenied|AuthFailure|UnauthorizedOperation" "${acct_dir}" 2>/dev/null; then
        warn "    此帳號掃描有錯誤，請先檢查報表總覽。"
      else
        echo -e "    ${CYAN}此帳號在所選 Region 內未回傳資源${NC}"
      fi
    fi
    echo ""
  done

  if [[ "$found_any" == "false" ]]; then
    if [[ -s "${out_base}/scan-errors.tsv" ]] ||
      grep -rqlE " - ERROR - |AccessDenied|AuthFailure|UnauthorizedOperation" "${out_base}" 2>/dev/null; then
      warn "未取得資源資料且發現掃描警告；請先檢查報表總覽，不代表帳號沒有資源。"
    else
      success "所選掃描範圍內未發現資源。"
    fi
  fi

  warn "S3、IAM 等 Global 服務會出現在每個 Region 目錄下，屬正常現象。"
  if [[ -s "${out_base}/scan-errors.tsv" ]] ||
    grep -rqlE " - ERROR - |AccessDenied|AuthFailure|UnauthorizedOperation" "${out_base}" 2>/dev/null; then
    echo ""
    warn "部分查詢可能失敗，請確認報表總覽的警告及 SSO Permission Set 權限。"
  fi
}

# -----------------------------------------------------------------------------
# 產生 Excel 報表
# -----------------------------------------------------------------------------
generate_report() {
  local run_ts="$1"
  local run_dir="${OUTPUT_BASE}/${run_ts}"
  local _args=(
    --run-dir "${run_dir}"
    --run-timestamp "${run_ts}"
  )

  if [[ "$COST_QUERY_ENABLED" == "true" ]]; then
    _args+=(
      --query-costs
      --cost-profile "${COST_PROFILE}"
      --cost-account-id "${COST_ACCOUNT_ID}"
      --start-month "${COST_START_MONTH}"
      --end-month "${COST_END_MONTH}"
    )
  fi

  for _profile in "${SELECTED_PROFILES[@]}"; do
    local _account_id="${PROFILE_ACCOUNT_IDS[$_profile]:-}"
    [[ -n "$_account_id" ]] && _args+=(--profile-account "${_profile}=${_account_id}")
  done
  for _region in "${SELECTED_REGIONS[@]}"; do
    _args+=(--region "${_region}")
  done
  for _category in "${SELECTED_CATS[@]}"; do
    _args+=(--category "${_category}")
  done

  "${PYTHON}" "${REPORT_PY}" "${_args[@]}"
}

# -----------------------------------------------------------------------------
# 主流程
# -----------------------------------------------------------------------------
main() {
  clear
  echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║      AWS Account Inventory Scanner           ║${NC}"
  echo -e "${BOLD}║      基於 aws-auto-inventory / scan.py       ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"

  preflight
  select_profiles
  select_regions
  select_categories
  select_cost_query

  local RUN_TS
  RUN_TS=$(date +"%Y%m%dT%H%M%S")
  mkdir -p "${OUTPUT_BASE}/${RUN_TS}"

  echo ""
  header "掃描確認"
  echo "  Profiles  : ${SELECTED_PROFILES[*]}"
  echo "  Regions   : ${SELECTED_REGIONS[*]}"
  echo "  類別      : ${SELECTED_CATS[*]}"
  echo "  輸出目錄  : ${OUTPUT_BASE}/${RUN_TS}/"
  if [[ "$COST_QUERY_ENABLED" == "true" ]]; then
    echo "  Cost Profile: ${COST_PROFILE}"
    echo "  費用期間  : ${COST_START_MONTH} 至 ${COST_END_MONTH}"
    echo "  費用查詢  : 已啟用（將產生 Cost Explorer API requests）"
  else
    echo "  費用查詢  : 已略過（不會呼叫 Cost Explorer）"
  fi
  echo ""
  # multiselect 用 read -rsn1 吃過 stdin，這裡明確從 /dev/tty 讀確認
  read -rp "確認開始掃描？(y/N) " _confirm < /dev/tty
  [[ "$_confirm" =~ ^[Yy]$ ]] || { info "已取消。"; exit 0; }

  if [[ "$COST_QUERY_ENABLED" == "true" ]]; then
    authenticate_cost_profile || true
  fi

  local _total=${#SELECTED_PROFILES[@]}
  local _idx=0
  for profile in "${SELECTED_PROFILES[@]}"; do
    _idx=$((_idx + 1))
    echo ""
    header "[${_idx}/${_total}] Profile: ${profile}"

    if ! ensure_sso_login "${profile}"; then
      warn "無法登入 Profile ${profile}，略過此帳號。"
      printf "%s\t\t%s\t%s\t%s\n" \
        "${profile}" "帳號識別" "登入失敗" \
        "Unable to obtain AWS caller identity." \
        >> "${OUTPUT_BASE}/${RUN_TS}/scan-errors.tsv"
      continue
    fi

    local account_id
    account_id=$(aws sts get-caller-identity --profile "${profile}" \
      --query 'Account' --output text 2>/dev/null || true)
    if [[ -z "$account_id" || "$account_id" == "None" ]]; then
      warn "無法取得 Profile ${profile} 的 Account ID，略過此帳號。"
      printf "%s\t\t%s\t%s\t%s\n" \
        "${profile}" "帳號識別" "失敗" \
        "Unable to obtain AWS Account ID." \
        >> "${OUTPUT_BASE}/${RUN_TS}/scan-errors.tsv"
      continue
    fi
    PROFILE_ACCOUNT_IDS["${profile}"]="${account_id}"
    info "Account ID: ${account_id}"

    run_scan "${profile}" "${account_id}" "${RUN_TS}"
    success "Profile ${profile} 掃描完成"
  done

  if ! generate_report "${RUN_TS}"; then
    error "Excel 報表產生失敗；JSON 掃描結果仍保留在 ${OUTPUT_BASE}/${RUN_TS}/"
    exit 1
  fi

  print_summary "${RUN_TS}"
}

main "$@"
