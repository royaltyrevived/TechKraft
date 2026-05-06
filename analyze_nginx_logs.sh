#!/bin/bash
LOG_FILE=$1
[[ ! -f "$LOG_FILE" ]] && echo "Log file not found" && exit 1

TOTAL=$(wc -l < "$LOG_FILE")
[[ "$TOTAL" -eq 0 ]] && echo "Log file is empty" && exit 0

calc_pct() {
  awk -v n="$1" -v t="$TOTAL" 'BEGIN { printf "%.2f", (n/t)*100 }'
}

ERR_4XX=$(awk '$9 ~ /^4/ {c++} END {print c+0}' "$LOG_FILE")
ERR_5XX=$(awk '$9 ~ /^5/ {c++} END {print c+0}' "$LOG_FILE")

echo "=== Nginx Log Analysis Report ==="
echo "Total Requests: $TOTAL"
echo "4xx Errors: $ERR_4XX ($(calc_pct "$ERR_4XX")%)"
echo "5xx Errors: $ERR_5XX ($(calc_pct "$ERR_5XX")%)"
echo -e "\nTop 10 IPs:"
awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -10
