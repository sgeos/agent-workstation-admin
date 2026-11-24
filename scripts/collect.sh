#!/bin/sh
# Copy this Mac's configuration into a folder so that git can record it.
#
# Usage: COLLECT_DEST=DIR scripts/collect.sh
#
# DIR defaults to ./machine, under the current directory. Keep the output in a
# private repository: it holds your dotfiles, your LaunchAgents, and lists of
# your installed software and services. In a checkout of this toolkit,
# machine/ is ignored by git, so that it is not published by accident. After
# collecting, review the diff and commit. The live files stay authoritative.
# The record is a copy of them, so a difference after collecting means that
# the machine changed, not that the record is wrong.
#
# What is collected: the files in home_files below, relative to $HOME, which
# are this toolkit's installed files and common dotfiles, plus any listed in
# COLLECT_FILES_EXTRA, separated by spaces, such as
#   COLLECT_FILES_EXTRA=".claude/settings.json .codex/config.toml"
# A path that does not exist is skipped and reported. Paths may not contain
# spaces. Then lists of LaunchAgents, launchd overrides, MacPorts or Homebrew
# packages and installed software versions, as text that diffs cleanly.
#
# Secrets are never collected on purpose, and every file that is copied is
# first scanned for secret-like strings. A match stops the script before
# anything is written, naming only the file and line numbers. Keep secrets in
# files that are not on the list, such as ~/.profile.secret sourced from
# ~/.profile.
#
# Redaction. Some harness configuration files hold OAuth client secrets inline,
# as `client_secret = "..."` in TOML. Every file passes through redact() before
# it is scanned and written, which replaces the value of such lines with a
# marker. The scan then runs on the redacted text, so a secret that redaction
# does not cover still stops the script. Redaction changes only the recorded
# copy, never the live file.
#
# Limits. The scan is a list of patterns for common credential formats, not a
# guarantee. A secret in an unusual format can pass it, so review the diff
# before committing, and keep the record private.
#
# The weekly report libexec/periodic/weekly/340.config-drift sets COLLECT_DEST
# to a temporary folder and compares the result with the last record.
#
# Exit status: 0 on success, 1 when a file holds a secret-like string, a path
# is refused or a listing fails.

set -eu

dest=${COLLECT_DEST:-$(pwd)/machine}

# Paths relative to $HOME. A path that does not exist is skipped and reported.
home_files="
.profile
.bash_profile
.bashrc
.zprofile
.zshrc
.gitconfig
.config/git/ignore
.vimrc
.config/periodic.conf
.config/rotate-logs.conf
.claude/statusline.sh
.local/bin/cargo-outdated-check
.local/bin/health-alert
.local/bin/machine-status
.local/bin/memwatch
.local/bin/periodic-run
.local/bin/rotate-logs
.local/bin/session-inventory
.local/libexec/periodic/daily/100.unsaved-work
.local/libexec/periodic/daily/200.disk-trend
.local/libexec/periodic/weekly/300.stale-worktrees
.local/libexec/periodic/weekly/310.github
.local/libexec/periodic/weekly/320.updates
.local/libexec/periodic/weekly/330.harness-logs
.local/libexec/periodic/weekly/340.config-drift
.local/libexec/periodic/weekly/350.build-growth
.local/share/health-alert/HealthAlert.applescript
.local/share/health-alert/build.sh
.local/share/machine-status/PLAYBOOK.md
Library/LaunchAgents/local.health-alert.plist
Library/LaunchAgents/local.machine-status.plist
Library/LaunchAgents/local.memwatch.plist
Library/LaunchAgents/local.periodic.daily.plist
Library/LaunchAgents/local.periodic.weekly.plist
Library/LaunchAgents/local.periodic.monthly.plist
Library/LaunchAgents/local.rotate-logs.plist
${COLLECT_FILES_EXTRA:-}
"

# Provider formats first: OpenAI and Anthropic, GitHub, xAI, Google OAuth and
# API keys, AWS, Slack, GitLab and npm tokens, and private keys. Then generic
# assignments. The upper-case alternative catches shell forms such as
# `API_KEY=...`. The lower-case alternative catches TOML and JSON forms such as
# `client_secret = "..."` and `"api_key": "..."`. A value starting with `<`,
# such as the redaction marker, does not match.
secret_pattern='(sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|xai-[A-Za-z0-9]{16,}|GOCSPX-[A-Za-z0-9_-]{8,}|AIza[0-9A-Za-z_-]{30,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{16,}|npm_[A-Za-z0-9]{30,}|_authToken[[:space:]]*=|-----BEGIN [A-Z ]*PRIVATE KEY|(TOKEN|KEY|SECRET|PASSWORD)[A-Z_]*=["'"'"']?[A-Za-z0-9/+_-]{12,}|(token|secret|password|api_key|apikey)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9/+_.-]{16,})'

# Print the file with inline OAuth client secrets replaced by a marker.
redact() {
    sed -E 's/^([[:space:]]*client_secret[[:space:]]*=[[:space:]]*)"[^"]*"/\1"<redacted by collect.sh>"/' "$1"
}

# Every path must stay inside $HOME and, once copied, inside the destination,
# so an absolute path or one with a .. component is refused.
for path in $home_files; do
    case /${path}/ in
        //*|*/../*)
            echo "refusing ${path}: paths must be relative to \$HOME without .." >&2
            exit 1 ;;
    esac
done

# Scan everything first, so that a match leaves the destination untouched.
found=false
for path in $home_files; do
    src=${HOME}/${path}
    [ -f "$src" ] || continue
    # grep exits 0 on a match, 1 on none and 2 on an error. An error must stop
    # the script, or a failed scan would pass a file unchecked. The scan reads
    # the redacted text, which is exactly what will be written.
    rc=0
    redacted=$(redact "$src") || {
        echo "redaction failed on ~/${path}; nothing collected" >&2
        exit 1
    }
    matches=$(printf '%s\n' "$redacted" | /usr/bin/grep -n -E "$secret_pattern") || rc=$?
    if [ "$rc" -gt 1 ]; then
        echo "secret scan failed on ~/${path}; nothing collected" >&2
        exit 1
    fi
    if [ "$rc" -eq 0 ]; then
        lines=$(printf '%s\n' "$matches" | cut -d: -f1 | tr '\n' ' ')
        echo "secret-like string in ~/${path}, lines ${lines}" >&2
        found=true
    fi
done
if [ "$found" = true ]; then
    echo "nothing collected; move the secrets out of those files first" >&2
    exit 1
fi

mkdir -p "${dest}/home"
for path in $home_files; do
    src=${HOME}/${path}
    if [ ! -f "$src" ]; then
        echo "skipped, not present: ~/${path}"
        continue
    fi
    out=${dest}/home/${path}
    mkdir -p "$(dirname "$out")"
    # Write the redacted text, then carry over the mode and modification time,
    # as cp -p would, so executable scripts stay executable in the record.
    redact "$src" > "${out}.tmp"
    chmod "$(stat -f %Lp "$src")" "${out}.tmp"
    touch -r "$src" "${out}.tmp"
    mv "${out}.tmp" "$out"
done

have() { command -v "$1" >/dev/null 2>&1; }

# Package and service state, as text that diffs cleanly. Each list is written
# even when its tool is missing, so a vanished tool shows as drift.
if have port; then
    port -q installed requested | awk '{ print $1 }' | sort -u > "${dest}/ports-requested.txt"
else
    echo "MacPorts not found" > "${dest}/ports-requested.txt"
fi
if have brew; then
    brew leaves 2>/dev/null | sort -u > "${dest}/brew-leaves.txt" || true
else
    echo "Homebrew not found" > "${dest}/brew-leaves.txt"
fi
launchctl print-disabled "gui/$(id -u)" | awk -F'"' '/=>/ { print $2, ($0 ~ /disabled/ ? "disabled" : "enabled") }' |
    sort > "${dest}/launchctl-gui.txt"
launchctl print-disabled system | awk -F'"' '/=>/ { print $2, ($0 ~ /disabled/ ? "disabled" : "enabled") }' |
    sort > "${dest}/launchctl-system.txt"
ls "${HOME}/Library/LaunchAgents" > "${dest}/launchagents-user.txt" 2>/dev/null || true
ls /Library/LaunchAgents /Library/LaunchDaemons > "${dest}/launchd-library.txt" 2>&1 || true
sw_vers > "${dest}/sw_vers.txt"

# Installed software versions, one file, so that git history records what was
# updated when. Each section is written even when its tool is missing, as
# "not found", so a vanished tool shows as drift rather than as silence. The
# periodic jobs run without ~/.cargo/bin on PATH, and uv may live under
# ~/Library/Python/<version>/bin, so both are found explicitly. Every command
# ends in `|| true` or is guarded, because set -e would otherwise stop the
# whole collection when one tool is missing.
PATH=${PATH}:${HOME}/.cargo/bin
# The glob sorts by name, so the last match is the newest Python's copy.
uv=$(command -v uv 2>/dev/null || true)
if [ -z "$uv" ]; then
    for candidate in "${HOME}"/Library/Python/*/bin/uv; do
        if [ -x "$candidate" ]; then uv=$candidate; fi
    done
fi
{
    echo "# Generated by scripts/collect.sh. Do not edit."
    echo "## harnesses"
    for tool in claude codex grok; do
        if have "$tool"; then
            printf '%s: %s\n' "$tool" "$("$tool" --version 2>/dev/null | head -1 || true)"
        else
            echo "${tool}: not found"
        fi
    done
    echo "## terminal apps"
    for app in ${COLLECT_APPS:-/Applications/Ghostty.app /Applications/iTerm.app}; do
        if [ -d "$app" ]; then
            printf '%s: %s\n' "${app##*/}" "$(defaults read "${app}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unreadable")"
        else
            echo "${app##*/}: not found"
        fi
    done
    echo "## rustup toolchains"
    if have rustup; then
        for t in $(rustup toolchain list 2>/dev/null | awk '{ print $1 }'); do
            printf '%s: %s\n' "$t" "$(rustc "+$t" --version 2>/dev/null || echo "not runnable")"
        done
    else
        echo "rustup not found"
    fi
    echo "## cargo install --list"
    if have cargo; then cargo install --list 2>/dev/null | grep -E '^[^ ]' || true; else echo "cargo not found"; fi
    echo "## npm -g"
    if have npm; then npm ls -g --depth=0 2>/dev/null | sed -n 's/^[├└]── //p' || true; else echo "npm not found"; fi
    echo "## uv tools"
    if [ -n "$uv" ] && [ -x "$uv" ]; then "$uv" tool list 2>/dev/null | grep -v '^-' || true; else echo "uv not found"; fi
    echo "## MacPorts active ports"
    if have port; then port -q installed active 2>/dev/null | awk '{ print $1, $2 }' | sort || true; else echo "port not found"; fi
    echo "## Homebrew"
    if have brew; then brew list --versions 2>/dev/null | sort || true; else echo "brew not found"; fi
} > "${dest}/software-versions.txt"

echo "collected into ${dest}; review the difference before committing"
