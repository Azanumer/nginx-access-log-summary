# nginx-access-log-summary

One-glance summary of an Nginx (or Apache combined-format) access log: request volume, bandwidth, status-code classes, top IPs / URLs / 404s, bot share, and request methods.

## Why

When traffic spikes, or Google Search Console shows crawl anomalies, you want answers in 5 seconds — not a monitoring install. This is a single awk pass that runs anywhere, reads the log read-only, and also emits JSON for cron/Nagios pipelines.

## Usage

```bash
./log-summary.sh /var/log/nginx/access.log
./log-summary.sh /var/log/nginx/access.log --top 20 --since "15/Oct/2026"
./log-summary.sh /var/log/nginx/access.log --json
```

## Example

```
Log: /var/log/nginx/access.log
Window: 15/Oct/2026:10:00:01  to  16/Oct/2026:09:00:00
Requests: 128431    Bandwidth: 4.2 GB    Bots: 18902 (14.7%)

-- Status classes --
  118204  2xx
    9120  4xx
    1107  5xx

-- Top 10 IPs by requests --
   18420  203.0.113.45
    ...

-- Top 10 404s by URL --
    2211  /wp-login.php
     640  /.env
```

Practical uses: spot brute-force IPs, find broken links worth redirecting, measure real bot/crawler share, confirm a traffic spike is humans (or not).

## License

MIT — see [LICENSE](LICENSE).
