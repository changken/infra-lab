#!/usr/bin/env bash
# 用途：驗證 WAF 規則（TODO 2）。用法：./attack_probe.sh <lb_public_ip>
# 預期：WAF 開啟前，3 種攻擊請求都回 200；開啟後 SQLi／XSS 回 403，rate limit 測試出現大量 403
LB="${1:?usage: $0 <lb_public_ip>}"

echo "== normal =="
curl -s -o /dev/null -w "%{http_code}\n" "http://$LB/"

echo "== sqli =="
curl -s -o /dev/null -w "%{http_code}\n" "http://$LB/?id=1%27%20OR%20%271%27=%271"

echo "== xss =="
curl -s -o /dev/null -w "%{http_code}\n" "http://$LB/?q=%3Cscript%3Ealert(1)%3C/script%3E"

echo "== rate limit（100 次，看 200／403 的分布）=="
for i in $(seq 1 100); do curl -s -o /dev/null -w "%{http_code}\n" "http://$LB/"; done | sort | uniq -c
