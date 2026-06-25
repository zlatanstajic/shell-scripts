---
layout: default
title: Rain Alert
parent: Scripts
nav_order: 13
---

# Rain Alert

**File:** `src/scripts/rain-alert.sh` · Email a rain alert when MET Norway
forecasts rain for any configured city within a lookahead window.

For each configured city the script queries the MET Norway
[Locationforecast 2.0 compact](https://api.met.no/weatherapi/locationforecast/2.0/documentation)
API, scans the forecast for the next `RAIN_ALERT_LOOKAHEAD_HOURS` hours, and
flags any hour whose `next_1_hours` symbol code matches `rain`/`sleet`/`thunder`
or whose precipitation amount exceeds `RAIN_ALERT_PRECIP_THRESHOLD_MM`. When at
least one city expects rain it composes a single email listing each rainy city
with the expected local times and sends it via `msmtp`.

It is built for an hourly cron: when **no** city expects rain it exits silently
and sends nothing, so the cron stays noise-free. A last-alert signature is
cached in `RAIN_ALERT_CACHE_FILE`; an unchanged forecast is not re-sent. The
cache is updated only after a real (non-dry-run) send.

`jq` and `curl` are hard dependencies (parsing and fetching). `msmtp` is a hard
dependency for a real send, but `-n/--dry-run` skips the send — it prints the
recipient, subject, and body that *would* be sent — so you can preview without
`msmtp` configured. Without `msmtp` you can also pipe the composed message to
`curl` over SMTP (see the example below and `-h`). For an ad-hoc check, `-d`/`--display`
prints the forecast straight to stdout and exits — no email, no recipient, and
no `msmtp` required.

MET Norway requires a descriptive `User-Agent` identifying your application and
a contact; set `RAIN_ALERT_USER_AGENT` accordingly. The script sleeps
`RAIN_ALERT_THROTTLE_SECONDS` between per-city requests to respect the terms of
service. Forecast timestamps are UTC (Zulu) and are converted to local time for
the email.

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `-n`, `--dry-run` | no | Print the email that would be sent; send nothing |
| `-d`, `--display` | no | Print the forecast to stdout and exit; sends no email, needs no recipient or `msmtp`, and never touches the cache |
| `-h`, `--help` | — | Print usage and exit (config via `.env`) |

## `.env` keys

`RAIN_ALERT_CITIES` (whitespace/comma-separated `name:lat:lon` list),
`RAIN_ALERT_LOOKAHEAD_HOURS`, `RAIN_ALERT_PRECIP_THRESHOLD_MM`,
`RAIN_ALERT_RECIPIENT` (required), `RAIN_ALERT_MSMTP_ACCOUNT`,
`RAIN_ALERT_USER_AGENT`, `RAIN_ALERT_THROTTLE_SECONDS`, `RAIN_ALERT_CACHE_FILE`

## Usage

```bash
# Show help
bash rain-alert.sh -h

# Run the check (driven by .env); emails only when rain is expected
bash rain-alert.sh

# Preview the would-send email without invoking msmtp
bash rain-alert.sh -n

# Hourly cron entry
0 * * * * /path/to/rain-alert.sh >/dev/null 2>&1
```

Without `msmtp`, pipe the composed message to `curl` over SMTP instead:

```bash
curl --ssl-reqd --mail-from you@example.com --mail-rcpt rcpt@example.com \
  --upload-file msg.txt --user you@example.com:pass smtps://smtp.host:465
```
