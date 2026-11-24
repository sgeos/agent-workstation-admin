#!/bin/sh
# Tests for bin/periodic-run in this repository, against temporary folders only.
# Run as: sh scripts/test-periodic.sh. Exit status is the number of failures.
#
# Checks: jobs run in name order and their output is collected; a report with
# ATTENTION lines, or a job that fails, queues one Health Alert line; a clean
# report queues nothing; a missing job folder is flagged; a second run while
# one holds the lock exits 1; and settings in periodic.conf reach the jobs.
# HOME points at the temporary folder, so the user's own periodic.conf is never
# read, and PERIODIC_KICKSTART=0 keeps the real Health Alert from starting.
set -u
pr=$(cd "$(dirname "$0")/../bin" && pwd)/periodic-run
d=$(mktemp -d)
fail=0
check() { # NAME EXPECTED ACTUAL
    if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=$((fail + 1)); fi
}
run() { # FREQUENCY
    HOME=$d PERIODIC_JOB_DIR=$d/jobs PERIODIC_LOG_DIR=$d/logs PERIODIC_STATE_DIR=$d/state \
    PERIODIC_QUEUE=$d/queue PERIODIC_KICKSTART=0 sh "$pr" "$1" >/dev/null 2>&1
}
job() { # FREQUENCY NAME BODY
    mkdir -p "$d/jobs/$1"
    printf '#!/bin/sh\n%s\n' "$3" > "$d/jobs/$1/$2"
    chmod 755 "$d/jobs/$1/$2"
}

job daily 100.first 'echo first-ran'
job daily 200.second 'echo second-ran'
run daily
check "a clean report exits 0" "0" "$?"
check "jobs run in name order" "first-ran second-ran" "$(grep -- '-ran$' "$d/logs/daily.out" | tr '\n' ' ' | sed 's/ $//')"
check "a clean report queues nothing" "no" "$([ -s "$d/queue" ] && echo yes || echo no)"

job weekly 100.finding 'echo "ATTENTION: something"'
job weekly 200.broken 'exit 3'
run weekly
check "findings queue one line" "1" "$(wc -l < "$d/queue" | tr -d ' ')"
check "the queue line counts both findings" "yes" "$(grep -q '2 findings' "$d/queue" && echo yes || echo no)"
check "a failing job is flagged" "yes" "$(grep -q 'ATTENTION: 200.broken exited with status 3' "$d/logs/weekly.out" && echo yes || echo no)"
: > "$d/queue"

run monthly
check "a missing job folder is flagged" "yes" "$(grep -q 'ATTENTION: no jobs found' "$d/logs/monthly.out" && echo yes || echo no)"
: > "$d/queue"

mkdir -p "$d/state/daily.lock"
run daily
check "a held lock exits 1" "1" "$?"
rmdir "$d/state/daily.lock"

mkdir -p "$d/.config"
echo 'PERIODIC_TEST_SETTING=from-conf' > "$d/.config/periodic.conf"
# Single quotes on purpose: the job, not this script, expands the variable.
# shellcheck disable=SC2016
job daily 300.setting 'echo "setting=${PERIODIC_TEST_SETTING:-unset}"'
run daily
check "periodic.conf settings reach the jobs" "yes" "$(grep -q 'setting=from-conf' "$d/logs/daily.out" && echo yes || echo no)"

rm -rf "$d"
echo "failures: $fail"
exit "$fail"
