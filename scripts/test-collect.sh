#!/bin/sh
# Tests for the secret scan, redaction and path checks in scripts/collect.sh.
# Run as: sh scripts/test-collect.sh. Exit status is the number of failures.
#
# Each planted fake secret must stop collection with nothing written, the
# inline client_secret form must be redacted instead, and harmless names of
# environment variables must pass. A throwaway HOME and destination are used,
# so the real record and the live files are never touched. The planted file is
# added to the list through COLLECT_FILES_EXTRA, which tests that too. The
# script still runs the real launchctl, sw_vers and package listings, writing
# their output only into the throwaway folder.
set -u
collect=$(cd "$(dirname "$0")" && pwd)/collect.sh
failures=0
run() {
    expect=$1
    payload=$2
    h=$(mktemp -d)
    t=$(mktemp -d)
    mkdir -p "$h/.codex" "$h/Library/LaunchAgents"
    printf '%s\n' "$payload" > "$h/.codex/config.toml"
    if HOME=$h COLLECT_DEST=$t COLLECT_FILES_EXTRA=.codex/config.toml "$collect" >/dev/null 2>"$t.err"; then
        got=collected
    else
        got=stopped
    fi
    written=""
    [ -f "$t/home/.codex/config.toml" ] && written=$(cat "$t/home/.codex/config.toml")
    if [ "$got" = "$expect" ]; then
        verdict=PASS
    else
        verdict=FAIL
        failures=$((failures + 1))
    fi
    # A stopped run must have written nothing.
    if [ "$got" = stopped ] && [ -n "$written" ]; then
        verdict=FAIL
        failures=$((failures + 1))
    fi
    # A redacted run must not have written the planted value.
    case $written in *abcdefghijklmnopqr*)
        verdict=FAIL
        failures=$((failures + 1)) ;;
    esac
    printf '%s expect=%s got=%s payload=[%s] written=[%s]\n' "$verdict" "$expect" "$got" "$payload" "$written"
    rm -rf "$h" "$t" "$t.err"
}
run stopped   'api_key = "abcdefghijklmnopqrstuv"'
run stopped   '"token": "abcdefghijklmnop1234"'
run stopped   'x = "GOCSPX-abcdefghijkl"'
run stopped   'OPENAI_API_KEY=abcdefghijklmnop'
run stopped   'x = "ghs_abcdefghijklmnopqrstuv"'
run stopped   'x = "xoxb-1234567890-abcdef"'
run stopped   '//registry.npmjs.org/:_authToken=whatever'
run stopped   '-----BEGIN OPENSSH PRIVATE KEY-----'
run collected 'client_secret = "abcdefghijklmnopqr"'
run collected 'bearer_token_env_var = "MAILBOX_TOKEN"'
run collected 'clientSecretEnvVar = "OAUTH_SECRET"'

# An extra path outside $HOME, or one that climbs out of it, must be refused
# before anything is written.
for bad in /etc/hosts ../outside .config/../../outside; do
    h=$(mktemp -d)
    t=$(mktemp -d)
    if HOME=$h COLLECT_DEST=$t COLLECT_FILES_EXTRA=$bad "$collect" >/dev/null 2>&1; then
        got=collected
    else
        got=stopped
    fi
    if [ "$got" = stopped ] && [ -z "$(ls -A "$t")" ]; then
        echo "PASS refuses extra path [$bad]"
    else
        echo "FAIL refuses extra path [$bad]: got=$got"
        failures=$((failures + 1))
    fi
    rm -rf "$h" "$t"
done
echo "failures: $failures"
exit "$failures"
