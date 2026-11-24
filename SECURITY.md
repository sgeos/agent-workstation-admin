# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| Unreleased, the default branch | Yes |

Replace this table at the first release, and keep it current with each release line.

## Reporting a vulnerability

Please report security issues privately, so that a fix can be prepared before public
disclosure. Open a draft advisory at
<https://github.com/sgeos/agent-workstation-admin/security/advisories/new>. The maintainer is
notified and can work on the fix with you in the same place.

Please include the affected version or commit, a minimal way to reproduce the issue, the
expected and observed behaviour, and your assessment of severity if you have one.

## Response

The maintainer aims to acknowledge a report within a few days, and to either confirm the
issue or explain why it is not a vulnerability. Confirmed issues are fixed in a release
whose disclosure timeline is agreed with the reporter.

## Scope

In scope are the scripts in `bin/`, `libexec/`, `share/`, `claude/` and `scripts/`, and the
templates in `launchd/` and `etc/`. The trust boundaries that matter most are these.

- `scripts/collect.sh` scans each file for secret-like strings before copying and redacts
  inline `client_secret` values. It is a safeguard against common credential formats, not
  a guarantee, and a secret in an unusual format can pass it. A report of a common format
  that it misses is in scope.
- `bin/periodic-run` executes `~/.config/periodic.conf` as shell, and every executable
  file in its job folders. Both carry the same trust as the user's own shell startup files.
- `claude/statusline.sh` runs `scripts/statusline-segment.sh` from the session's working
  directory when that file is executable, so a session opened in an untrusted checkout runs
  that checkout's script. `STATUSLINE_PROJECT_SEGMENT=0` turns this off.
- `bin/rotate-logs` deletes old MCP Agent Mail backups by exact name and age. A way to make
  it delete anything else is in scope.
- Health Alert and memwatch place text in AppleScript source. memwatch sanitizes process
  names first. A way to inject AppleScript through them is in scope.

Out of scope are the behaviour of macOS, launchd, the agent harnesses themselves, and
configuration that the user writes into the files above.
