#!/usr/bin/env bash
#
# log-summary.sh — one-glance summary of an Nginx (or Apache combined-format)
# access log: request volume, bandwidth, status codes, top IPs / URLs / 404s,
# bot share, and slowest-looking large transfers.
#
# Why: when traffic spikes or Google Search Console shows crawl anomalies, you
# want answers in 5 seconds, not a GoAccess install. This runs anywhere awk
# exists and never modifies the log.
#
# Usage:
#   ./log-summary.sh /var/log/nginx/access.log
#   ./log-summary.sh /var/log/nginx/access.log --top 20 --since "15/Oct/2026"
#   ./log-summary.sh /var/log/nginx/access.log --json
#
# Flags:
#   --top N        how many rows for the Top-N sections (default 10)
#   --since DATE   only entries at/after this log timestamp, e.g. "15/Oct/2026"
#   --json         machine-readable output
#   -h, --help     this help

set -u

FILE="" TOP=10 SINCE="" JSON=0

usage() { sed -n '2,17p' "$0" | sed 's/^# \?//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --top)   TOP="$2";   shift 2 ;;
        --since) SINCE="$2"; shift 2 ;;
        --json)  JSON=1;     shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 2 ;;
        *)  FILE="$1"; shift ;;
    esac
done

[ -z "$FILE" ] && { echo "Error: no log file given." >&2; usage; exit 2; }
[ -r "$FILE" ] || { echo "Error: cannot read $FILE" >&2; exit 2; }
command -v awk >/dev/null || { echo "Error: awk not found." >&2; exit 2; }

# --- format detection: warn if the file does not look like a combined log ----
if ! head -c 4096 "$FILE" | grep -qE '"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) '; then
    echo "Warning: $FILE does not look like a combined-format access log; results may be off." >&2
fi

# Single-pass awk: parse combined log lines, collect counters, print report.
# $1=IP  $4=[day/mon/year  $6="METHOD  $7=path  $9=status  $10=bytes  $12="UA
awk -v top="$TOP" -v since="$SINCE" -v json="$JSON" '
function human(bytes,    u) {
    u = "B"
    if (bytes >= 1073741824) { bytes /= 1073741824; u = "GB" }
    else if (bytes >= 1048576) { bytes /= 1048576; u = "MB" }
    else if (bytes >= 1024)    { bytes /= 1024;    u = "KB" }
    return sprintf("%.1f %s", bytes, u)
}
function strip_ts(s) { gsub(/^\[|\]$/, "", s); return s }   # "[15/Oct/2026:10:00:00" -> "15/Oct/2026:10:00:00"
BEGIN {
    total = 0; bytes = 0; bots = 0
    months["Jan"]=1; months["Feb"]=2; months["Mar"]=3; months["Apr"]=4
    months["May"]=5; months["Jun"]=6; months["Jul"]=7; months["Aug"]=8
    months["Sep"]=9; months["Oct"]=10; months["Nov"]=11; months["Dec"]=12
    if (since != "") {
        # accept "15/Oct/2026" or "15/Oct/2026:10:30:00"
        n = split(since, p, "[/:]")
        since_key = sprintf("%04d%02d%02d%02d%02d%02d", p[3], months[p[2]], p[1], (n>3?p[4]:0), (n>4?p[5]:0), (n>5?p[6]:0))
    }
}
{
    ts = strip_ts($4)
    if (since != "") {
        n = split(ts, q, "[/:]")
        key = sprintf("%04d%02d%02d%02d%02d%02d", q[3], months[q[2]], q[1], q[4], q[5], q[6])
        if (key < since_key) next
    }
    ip = $1
    method = substr($6, 2)                                  # strip leading quote: "GET -> GET
    path = $7; sub(/\?.*$/, "", path)                       # strip query string
    status = $9 + 0
    size = ($10 == "-") ? 0 : $10 + 0
    ua = ""; for (i = 12; i <= NF; i++) ua = ua $i " "      # last quoted field

    total++; bytes += size
    ips[ip]++
    urls[path]++
    methods[method]++
    classes[int(status/100)]++
    if (status == 404) notfound[path]++
    if (ua ~ /[Bb]ot|[Ss]pider|[Cc]rawl|[Ss]lurp|Mediapartners|APIs-Google/) bots++

    if (min_ts == "" || ts < min_ts) min_ts = ts
    if (max_ts == "" || ts > max_ts) max_ts = ts
}
function topn(arr, label,    n, k, keys, j, tmp, out) {
    # insertion-sort top-N (fine for log-scale key counts)
    n = 0
    for (k in arr) { keys[++n] = k }
    for (i = 1; i <= n; i++)
        for (j = i + 1; j <= n; j++)
            if (arr[keys[j]] > arr[keys[i]]) { tmp = keys[i]; keys[i] = keys[j]; keys[j] = tmp }
    if (json) {
        out = ""
        for (i = 1; i <= (n < top ? n : top); i++)
            out = out (out == "" ? "" : ",") sprintf("{\"key\":\"%s\",\"hits\":%d}", keys[i], arr[keys[i]])
        printf "\"%s\":[%s]", label, out
        return
    }
    printf "\n-- Top %d %s --\n", (n < top ? n : top), label
    for (i = 1; i <= (n < top ? n : top); i++)
        printf "%8d  %s\n", arr[keys[i]], keys[i]
}
END {
    if (total == 0) { print "No entries matched." > "/dev/stderr"; exit 0 }
    if (json) {
        printf "{\"file\":\"%s\",\"window\":\"%s to %s\",\"requests\":%d,\"bandwidth_bytes\":%d,",
               FILENAME, min_ts, max_ts, total, bytes
        printf "\"bots\":%d,\"bot_pct\":%.1f,", bots, (bots/total*100)
        printf "\"status\":{"
        sep = ""
        for (c = 1; c <= 5; c++) if (classes[c] > 0) { printf "%s\"%dxx\":%d", sep, c, classes[c]; sep = "," }
        printf "},"
        topn(ips, "ips"); printf ","; topn(urls, "urls"); printf ","; topn(notfound, "not_found")
        printf "}\n"
        exit 0
    }
    printf "Log: %s\nWindow: %s  to  %s\n", FILENAME, min_ts, max_ts
    printf "Requests: %d    Bandwidth: %s    Bots: %d (%.1f%%)\n",
           total, human(bytes), bots, (bots/total*100)
    printf "\n-- Status classes --\n"
    for (c = 1; c <= 5; c++)
        if (classes[c] > 0) printf "%8d  %dxx\n", classes[c], c
    printf "\n-- Methods --\n"
    for (m in methods) printf "%8d  %s\n", methods[m], m
    topn(ips, "IPs by requests")
    topn(urls, "URLs by requests")
    topn(notfound, "404s by URL")
}
' "$FILE"
