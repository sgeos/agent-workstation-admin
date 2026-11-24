#!/bin/sh
# Install the toolkit into the current account's home folder.
#
# Usage: scripts/install.sh [--apply] [SECTION...]
#
# Without --apply nothing is changed. Every action is printed with "would",
# so a first run shows exactly what the script would do. With no SECTION, the
# files and agents sections run, in that order. The others run only when named.
#
#   files       install bin/ into ~/.local/bin, libexec/periodic/ into
#               ~/.local/libexec/periodic, share/ into ~/.local/share, and
#               launchd/*.plist.in into ~/Library/LaunchAgents as *.plist,
#               with @HOME@ replaced by $HOME
#   agents      build ~/Applications/Health Alert.app and load, or reload, each
#               LaunchAgent that the files section installs
#   statusline  install claude/statusline.sh as ~/.claude/statusline.sh. The
#               Claude Code settings file is never edited. The line to add to
#               it is printed instead.
#   newsyslog   with sudo: install etc/newsyslog.d/local.conf.in as
#               /etc/newsyslog.d/local.conf, with @HOME@ and @USER@ replaced
#   touchid     with sudo: install etc/pam.d/sudo_local, which lets sudo accept
#               Touch ID
#   sshd        with sudo: install etc/ssh/sshd_config.d/050-hardening.conf.in,
#               with @USER@ replaced, and check it with sshd -t. It allows key
#               logins only, for this account only, so add a key to
#               ~/.ssh/authorized_keys before turning Remote Login on.
#
# A file that differs from the one being installed is first copied to
# ~/.local/state/agent-workstation-admin/backups/<time>/, keeping its path. The
# backups are kept outside the installed folders on purpose. periodic-run runs
# every executable file in its job folders, so a backup beside a job would run
# as a job, and newsyslog and sshd read every file in their .d folders. An identical file is left alone, so the
# script is idempotent.
#
# Run it as the daily user, not as root. Steps that need root call sudo
# themselves, and only in the sections that say so. Nothing is ever deleted.
# To uninstall, see the README.
#
# Exit status: 0 on success, 1 when a step fails or a precondition is not
# met, and 2 on a usage error.

set -eu

usage() {
    echo "usage: install.sh [--apply] [files|agents|statusline|newsyslog|touchid|sshd]..." >&2
    exit 2
}

die() {
    echo "install.sh: $*" >&2
    exit 1
}

apply=false
sections=
for arg in "$@"; do
    case $arg in
        --apply) apply=true ;;
        files|agents|statusline|newsyslog|touchid|sshd) sections="${sections} ${arg}" ;;
        *) usage ;;
    esac
done
[ -n "$sections" ] || sections=" files agents"

[ "$(uname -s)" = Darwin ] || die "this toolkit runs on macOS only"
[ "$(id -u)" -ne 0 ] || die "run as the daily user, not as root; steps that need root use sudo"

root=$(cd "$(dirname "$0")/.." && pwd)
[ -d "${root}/bin" ] && [ -d "${root}/launchd" ] || die "${root} does not look like a checkout of this toolkit"

user=$(id -un)
# The values are placed in sed replacements, which use # as the delimiter and
# give & and backslash a meaning. A home folder or user name holding any of
# them, or a relative home folder, is refused rather than mangled.
case $HOME in
    /*) ;;
    *) die "HOME must be an absolute path, got '${HOME}'" ;;
esac
case "${HOME}${user}" in
    *'#'*|*'&'*|*"\\"*) die "HOME or the user name contains #, & or a backslash, which this script does not support" ;;
esac

stamp=$(date +%Y%m%d%H%M%S)
backups=${HOME}/.local/state/agent-workstation-admin/backups/${stamp}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

say() {
    printf '%s\n' "$*"
}

# run COMMAND...: run it, or print it in a dry run.
run() {
    if [ "$apply" = true ]; then
        "$@"
    else
        say "  would run: $*"
    fi
}

# render SRC DEST: copy SRC to DEST, replacing the placeholders when SRC is a
# template, and keep it executable when SRC is.
render() {
    case $1 in
        *.in) sed -e "s#@HOME@#${HOME}#g" -e "s#@USER@#${user}#g" "$1" > "$2" ;;
        *) cat "$1" > "$2" ;;
    esac
    if [ -x "$1" ]; then chmod 755 "$2"; else chmod 644 "$2"; fi
}

# place SRC DEST: install SRC as DEST in the home folder, backing up a
# different file first. Prints what it does, or would do.
place() {
    rendered=${work}/rendered
    render "$1" "$rendered"
    if [ -f "$2" ] && cmp -s "$rendered" "$2"; then
        return 0
    fi
    rel=${2#"${HOME}"/}
    if [ -e "$2" ]; then
        say "  update ~/${rel}, keeping the old file under ~/${backups#"${HOME}"/}/"
        # ditto creates the parent folders and keeps the mode and times.
        run ditto "$2" "${backups}/${rel}"
    else
        say "  install ~/${rel}"
    fi
    [ -d "$(dirname "$2")" ] || run mkdir -p "$(dirname "$2")"
    if [ -x "$rendered" ]; then mode=755; else mode=644; fi
    run install -m "$mode" "$rendered" "$2"
    changed=$((changed + 1))
}

# install_tree SRC_DIR DEST_DIR: place every file under SRC_DIR, except the
# .gitkeep markers, and create every directory, including empty ones.
install_tree() {
    (cd "$1" && find . -type d | sed 's#^\./##' | sort) > "${work}/dirs"
    while IFS= read -r rel; do
        [ "$rel" = . ] && continue
        [ -d "${2}/${rel}" ] || run mkdir -p "${2}/${rel}"
    done < "${work}/dirs"
    (cd "$1" && find . -type f ! -name .gitkeep | sed 's#^\./##' | sort) > "${work}/files"
    while IFS= read -r rel; do
        place "${1}/${rel}" "${2}/${rel}"
    done < "${work}/files"
}

section_files() {
    say "== files: install into ${HOME}"
    changed=0
    install_tree "${root}/bin" "${HOME}/.local/bin"
    install_tree "${root}/libexec" "${HOME}/.local/libexec"
    install_tree "${root}/share" "${HOME}/.local/share"
    for template in "${root}"/launchd/*.plist.in; do
        name=$(basename "$template" .in)
        place "$template" "${HOME}/Library/LaunchAgents/${name}"
    done
    say "  ${changed} files to install or update"
}

section_agents() {
    say "== agents: build Health Alert and load the LaunchAgents"
    command -v osacompile >/dev/null || die "osacompile not found"
    build=${HOME}/.local/share/health-alert/build.sh
    if [ "$apply" = true ] && [ ! -f "$build" ]; then
        die "${build} not found; run the files section first"
    fi
    run sh "$build"
    domain=gui/$(id -u)
    for template in "${root}"/launchd/*.plist.in; do
        label=$(basename "$template" .plist.in)
        plist=${HOME}/Library/LaunchAgents/${label}.plist
        if [ "$apply" = true ] && [ ! -f "$plist" ]; then
            die "${plist} not found; run the files section first"
        fi
        # A loaded agent keeps its old definition until it is booted out.
        if launchctl print "${domain}/${label}" >/dev/null 2>&1; then
            run launchctl bootout "${domain}/${label}"
        fi
        run launchctl bootstrap "$domain" "$plist"
    done
}

section_statusline() {
    say "== statusline: install the Claude Code status line"
    changed=0
    place "${root}/claude/statusline.sh" "${HOME}/.claude/statusline.sh"
    command -v jq >/dev/null 2>&1 || say "  note: the status line needs jq, which is not on PATH"
    say "  To use it, add this to ~/.claude/settings.json; this script does not edit it:"
    say '    "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }'
}

# install_etc SRC DEST MODE: install SRC as DEST, owned by root, with sudo.
install_etc() {
    rendered=${work}/etc.rendered
    render "$1" "$rendered"
    if [ -f "$2" ] && cmp -s "$rendered" "$2"; then
        say "  $2 is current"
        return 0
    fi
    # The old file is kept in the user's backup folder, not beside the live
    # one, because newsyslog and sshd read every file in their .d folders and
    # would read a backup there as configuration.
    if [ -e "$2" ]; then
        say "  $2 differs and will be replaced; the old file is kept under ~/${backups#"${HOME}"/}/"
        run ditto "$2" "${backups}$2"
    fi
    run sudo install -d -m 755 -o root -g wheel "$(dirname "$2")"
    run sudo install -m "$3" -o root -g wheel "$rendered" "$2"
}

section_newsyslog() {
    say "== newsyslog: rotate the toolkit's logs"
    install_etc "${root}/etc/newsyslog.d/local.conf.in" /etc/newsyslog.d/local.conf 644
}

section_touchid() {
    say "== touchid: let sudo accept Touch ID"
    install_etc "${root}/etc/pam.d/sudo_local" /etc/pam.d/sudo_local 444
}

section_sshd() {
    say "== sshd: harden sshd for when Remote Login is on"
    [ -s "${HOME}/.ssh/authorized_keys" ] ||
        say "  note: ~/.ssh/authorized_keys is empty or unreadable; key logins will fail until a key is added"
    install_etc "${root}/etc/ssh/sshd_config.d/050-hardening.conf.in" \
        /etc/ssh/sshd_config.d/050-hardening.conf 644
    run sudo /usr/sbin/sshd -t
}

if [ "$apply" = true ]; then
    say "Applying sections:${sections}"
else
    say "Dry run of sections:${sections}. Nothing is changed; rerun with --apply."
fi
for section in $sections; do
    "section_${section}"
done
