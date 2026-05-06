#!/bin/bash
LOG_FILE=$1 [cite: 172]
[[ ! -f "$LOG_FILE" ]] && echo "Log file not found" && exit 1

TOTAL_REQ=$(wc -l < "$LOG_FILE") [cite: 175]
[[ "$TOTAL_REQ" -eq 0 ]] && echo "Empty log" && exit 0

UNIQUE_IPS=$(awk '{print $1}' "$LOG_FILE" | sort -u | wc -l) [cite: 176]
ERR_4XX=$(awk '$9 ~ /^4/ {c++} END {print c+0}' "$LOG_FILE") [cite: 177]
ERR_5XX=$(awk '$9 ~ /^5/ {c++} END {print c+0}' "$LOG_FILE") [cite: 178]

calc_pct() { awk -v n="$1" -v t="$TOTAL_REQ" 'BEGIN {printf "%.2f", (n/t)*100}'; }

echo "=== Nginx Log Analysis Report ==="
echo "Total Requests: $TOTAL_REQ"
echo "4xx Errors: $ERR_4XX ($(calc_pct "$ERR_4XX")%)"
echo "5xx Errors: $ERR_5XX ($(calc_pct "$ERR_5XX")%)"

echo -e "\nTop 10 IPs:" [cite: 179]
awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -10 [cite: 180, 182]

echo -e "\nTop 10 Endpoints:" [cite: 170, 183]
awk '{print $7}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -10 [cite: 184]
