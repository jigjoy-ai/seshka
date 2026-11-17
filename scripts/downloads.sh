#!/bin/bash
# Counts downloads from the CDN's access logs. deploy/releases.yaml turns the logs on and deletes them after
# 30 days, so this only sees the last month. CloudFront delivers a log up to an hour after the requests.
#
#   SESHKA_AWS_PROFILE=my-profile scripts/downloads.sh
#
# One line per day (UTC):
#   downloads   times the disk image was fetched in full
#   people      different addresses that fetched it
#   updates     installed copies that fetched a new version
#   installs    different addresses whose installed copy checked for an update
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SESHKA_AWS_PROFILE:?set SESHKA_AWS_PROFILE to an AWS profile that can read the logs bucket}"
LOGS=$(aws cloudformation describe-stacks --profile "$SESHKA_AWS_PROFILE" --region eu-west-1 --stack-name seshka-releases \
    --query "Stacks[0].Outputs[?OutputKey=='LogsBucket'].OutputValue" --output text)
[ -n "$LOGS" ] && [ "$LOGS" != None ] || { echo "No logs bucket in the seshka-releases stack; deploy deploy/releases.yaml first"; exit 1; }

DIR=dist/cdn-logs
mkdir -p "$DIR"
aws s3 sync "s3://$LOGS/cdn/" "$DIR" --profile "$SESHKA_AWS_PROFILE" --only-show-errors
if ! ls "$DIR"/*.gz >/dev/null 2>&1; then
    echo "No logs yet. CloudFront delivers them up to an hour after the requests."
    exit 0
fi

# Fields: 1 date, 4 bytes sent, 5 address, 6 method, 8 path, 9 status, 11 user agent.
# A download counts once most of the file went out: browsers probe and abandon, and those still log as 200.
# Only the app itself (Sparkle) counts as an install checking the feed, not a person or a script reading it.
gzip -dc "$DIR"/*.gz | awk -F'\t' '
    /^#/ { next }
    { days[$1] = 1 }
    $6 != "GET" { next }
    $8 == "/Seshka.dmg" && $9 == 200 && $4 >= 1000000 { downloads[$1]++; if (!seen["d", $1, $5]++) people[$1]++ }
    $8 ~ /^\/Seshka-.*\.zip$/ && $9 == 200 && $4 >= 1000000 { updates[$1]++ }
    $8 == "/appcast.xml" && ($9 == 200 || $9 == 304) && $11 ~ /Sparkle/ { if (!seen["a", $1, $5]++) installs[$1]++ }
    END {
        printf "%-12s %9s %7s %8s %9s\n", "day", "downloads", "people", "updates", "installs"
        for (day in days) {
            printf "%-12s %9d %7d %8d %9d\n", day, downloads[day], people[day], updates[day], installs[day] | "sort"
            total += downloads[day]
        }
        close("sort")
        printf "%-12s %9d\n", "total", total
    }'
