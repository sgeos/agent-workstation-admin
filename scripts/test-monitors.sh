#!/bin/sh
# Run as: sh scripts/test-monitors.sh. Exit status is the number of failures.
# Tests for the Health Alert backoff, the staleness watchdogs and memwatch's
# check on Health Alert, run against this repository's copies in bin/. Every
# run uses temporary state, logs and inputs, prints instead of notifying, and
# never touches the live state or logs. The disk check is forced critical by an
# impossible threshold, so the tests do not depend on the real free space.
# Coverage gap: the memory, SMART and uptime readings themselves are not
# tested, because they read the live machine.
set -u
bin=$(cd "$(dirname "$0")/../bin" && pwd)
HA=$bin/health-alert
MW=$bin/memwatch
d=$(mktemp -d)
fresh=$d/fresh; : > "$fresh"
old=$d/old; : > "$old"; touch -t 202601010000 "$old"
fail=0
check() { # NAME EXPECTED ACTUAL
    if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=$((fail + 1)); fi
}
ha() { # run health-alert; print only disk lines
    HEALTH_STATE_DIR=$d/state HEALTH_LOG=$d/ha.log HEALTH_MEMORY_LOG=/dev/null \
    HEALTH_DISK_CRIT_GB=999999 HEALTH_SAMPLER_STATUS="${SAMPLER:-$fresh}" HEALTH_MEMWATCH_LOG="$fresh" \
    "$HA" --print 2>/dev/null | cut -d'|' -f1,2 | grep "${1:-disk space}" | head -1
}
st() { cat "$d/state/disk" 2>/dev/null; }
now=$(date +%s)
title=$(ha | cut -d'|' -f2)
check "first run alerts critical" "critical|$title" "$(ha >/dev/null; rm -rf "$d/state"; ha)"
check "immediate repeat is quiet" "" "$(ha)"
check "state holds interval 3600" "3600" "$(st | awk '{print $3}')"
printf 'critical %s 3600\n' $((now - 3601)) > "$d/state/disk"
check "repeat after 1h alerts" "critical|$title" "$(ha)"
check "interval doubles to 7200" "7200" "$(st | awk '{print $3}')"
printf 'critical %s 7200\n' $((now - 3601)) > "$d/state/disk"
check "1h into a 2h interval is quiet" "" "$(ha)"
printf 'critical %s 86400\n' $((now - 86401)) > "$d/state/disk"
check "max interval repeat alerts" "critical|$title" "$(ha)"
check "interval capped at 86400" "86400" "$(st | awk '{print $3}')"
printf 'critical %s\n' $((now - 3601)) > "$d/state/disk"
check "old two-field state still repeats" "critical|$title" "$(ha)"
printf 'warning %s 86400\n' $((now - 60)) > "$d/state/disk"
check "warning to critical alerts at once" "critical|$title" "$(ha)"
check "missing sampler output warns" "warning" "$(SAMPLER=$d/missing ha 'Machine status' | cut -d'|' -f1)"
rm -f "$d/state/sampler"; check "stale sampler output warns" "warning" "$(SAMPLER=$old ha 'Machine status' | cut -d'|' -f1)"
rm -f "$d/state/sampler"
check "fresh sampler output is quiet" "" "$(SAMPLER=$fresh ha 'Machine status')"
# memwatch: check only the health-alert lines in its own log.
MEMWATCH_NOTIFY=0 MEMWATCH_LOG=$d/mw.log MEMWATCH_STATE_DIR=$d/mw MEMWATCH_HEALTH_LOG=$old "$MW" >/dev/null 2>&1
check "memwatch warns on stale Health Alert" "1" "$(grep -c 'WARN health-alert last sampled' "$d/mw.log")"
: > "$d/mw.log"
MEMWATCH_NOTIFY=0 MEMWATCH_LOG=$d/mw.log MEMWATCH_STATE_DIR=$d/mw MEMWATCH_HEALTH_LOG=$fresh "$MW" >/dev/null 2>&1
check "memwatch quiet on fresh Health Alert" "0" "$(grep -c 'health-alert' "$d/mw.log")"
rm -rf "$d"
echo "failures: $fail"
exit "$fail"
