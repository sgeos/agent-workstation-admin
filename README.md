# agent-workstation-admin

[![CI](https://github.com/sgeos/agent-workstation-admin/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/sgeos/agent-workstation-admin/actions/workflows/ci.yml)
[![License: 0BSD](https://img.shields.io/badge/license-0BSD-blue.svg)](LICENSE)

A small toolkit for administering one macOS workstation that runs many artificial
intelligence coding-agent sessions at once, such as Claude Code, Codex and Grok Build.

## Why

An agent session is cheap to start and easy to forget. A workstation that hosts a dozen of
them, each with its own builds, test runs and verifiers, is routinely overcommitted. Memory
fills, swap grows onto the system disk, build output takes hundreds of gigabytes, and a
single session can start enough parallel work to exhaust the machine within minutes. The
sessions themselves usually cannot see any of this, because agent sandboxes refuse `ps` and
often `sysctl`.

This toolkit gives the operator early warning and gives the sessions a view of the machine.
It prefers visibility over hard limits. Sessions read a status file and are asked to wait,
pause or lower their own parallelism, rather than being capped or killed. Every scheduled
check reports and leaves decisions to people.

## Components

**Health Alert.** `bin/health-alert` checks free disk space, the kernel's memory pressure and
swap in use, the solid-state drive's Self-Monitoring, Analysis and Reporting Technology
(SMART) data, uptime, and whether the other monitors are still running. A launchd job runs it
every ten minutes through a small AppleScript applet, built from `share/health-alert/`, so
that macOS names the notifications after Health Alert. A sustained condition repeats with a
doubling interval, from one hour up to one day, so a known problem does not become noise.
Each run also appends one memory sample to a log, which shows how quickly memory fills after
a restart.

**Machine status.** `bin/machine-status sample` runs every minute outside any sandbox and
writes a plain text file of key and value lines, followed by the largest sessions and
processes by memory footprint. Processes are attributed to Claude Code, Codex and Grok Build
sessions by walking their parent chains. Any session may run `machine-status`, which prints
the file and exits with 0 for ok, 1 for elevated, 2 for critical and 3 for stale.
`share/machine-status/PLAYBOOK.md` tells sessions how to act on each level, and is written so
that it can be cited from a project's agent instructions.

**memwatch.** `bin/memwatch` runs hourly and logs swap, free memory, free disk and any
process above a size limit, with a notification for each breach at most once in six hours.
It also warns when Health Alert has stopped writing samples, while Health Alert warns when
memwatch has stopped, so each monitor watches the other.

**Periodic reports.** `bin/periodic-run` runs the executable files in
`~/.local/libexec/periodic/daily/`, `weekly/` and `monthly/` in name order, in the manner of
FreeBSD's periodic(8), and writes their combined output to `~/Library/Logs/periodic/`. A job
flags a finding by printing a line that starts with `ATTENTION:`, and a report with findings
sends one notification through Health Alert. The jobs only read.

| Job | Frequency | Reports |
|---|---|---|
| `100.unsaved-work` | daily | uncommitted changes, unpushed commits, stashes and repositories with no remote |
| `200.disk-trend` | daily | used and free space on each volume, and growth since the previous day |
| `300.stale-worktrees` | weekly | git worktrees that are merged and idle, long idle, or missing |
| `310.github` | weekly | open Dependabot alerts, open pull requests, failing and stuck workflow runs |
| `320.updates` | weekly | available updates for macOS, MacPorts, Homebrew, the harnesses, npm, Rust, uv and cargo |
| `330.harness-logs` | weekly | the disk used by harness session transcripts, and any single large transcript |
| `340.config-drift` | weekly | configuration that differs from the last recorded collection |
| `350.build-growth` | weekly | the size and weekly growth of build output, caches and harness data |

**Log rotation.** newsyslog rotates the logs that each run opens afresh, through
`etc/newsyslog.d/local.conf.in`. `bin/rotate-logs` handles logs that a long-running service
holds open, which newsyslog cannot rotate safely. It compresses a copy, verifies the archive,
and only then truncates the live file. By default it rotates the logs of an MCP Agent Mail
server, where MCP stands for Model Context Protocol, and prunes that server's old database
backups. It does nothing on a machine without one.

**Session inventory.** `bin/session-inventory` prints one tab-separated row for each running
Claude Code, Codex and Grok Build session, with its name, identifier, harness version, model,
reasoning effort and working directory. It reads the harnesses' own session records and never
writes. It is useful for keeping a list of sessions to resume after a planned restart.

**Status line.** `claude/statusline.sh` is a Claude Code status line that shows the context
window's fill, the five-hour and seven-day account usage, the model and its reasoning effort,
the directory and the git branch. A project may add one segment of its own through an
executable `scripts/statusline-segment.sh`, which runs under a one-second timeout.

**Configuration collector.** `scripts/collect.sh` copies the files this toolkit installs, common
dotfiles and any others you list into a folder, together with lists of LaunchAgents, launchd
overrides, packages and installed software versions, so that git can record the machine's
configuration over time. It scans every file for secret-like strings before writing anything,
and stops when it finds one. It redacts inline `client_secret` values instead. Keep its output
in a private repository.

**Helpers and system files.** `bin/cargo-outdated-check` lists cargo-installed binaries with a
newer release on crates.io, for the weekly updates report. `etc/` holds optional system files,
which are a newsyslog configuration, a `sudo_local` that lets sudo accept Touch ID, and a Secure
Shell (SSH) daemon configuration that allows key logins only.

## Requirements

- macOS on Apple silicon. Development and testing used macOS 27.
- The system `sh`, `bash`, `python3`, `osacompile` and `plutil`. `python3` needs the Xcode
  Command Line Tools.
- Optional tools, each used only when present. These are `smartctl` from smartmontools for
  the SMART check, `jq` for the status line, `gh`, the GitHub command-line tool, for
  `310.github`, and MacPorts, Homebrew, npm, rustup, uv and cargo for `320.updates`.

## Install

Review what the installer would do, then apply it.

```sh
git clone https://github.com/sgeos/agent-workstation-admin.git
cd agent-workstation-admin
sh scripts/install.sh            # dry run, which changes nothing
sh scripts/install.sh --apply    # install the files and load the LaunchAgents
```

By default the installer runs two sections. The `files` section copies `bin/` to
`~/.local/bin`, `libexec/periodic/` to `~/.local/libexec/periodic`, `share/` to
`~/.local/share`, and each `launchd/*.plist.in` to `~/Library/LaunchAgents` with the home
folder filled in. The `agents` section builds `~/Applications/Health Alert.app` and loads, or
reloads, each LaunchAgent. A changed file is backed up first under
`~/.local/state/agent-workstation-admin/backups/`, and an unchanged file is left alone, so the
installer may be run again after every update.

Four further sections run only when named.

```sh
sh scripts/install.sh --apply statusline   # ~/.claude/statusline.sh, and prints the settings line
sh scripts/install.sh --apply newsyslog    # /etc/newsyslog.d/local.conf, with sudo
sh scripts/install.sh --apply touchid      # /etc/pam.d/sudo_local, with sudo
sh scripts/install.sh --apply sshd         # /etc/ssh/sshd_config.d/050-hardening.conf, with sudo
```

The installer never edits `~/.claude/settings.json`. It prints the line to add instead. Put
`~/.local/bin` on your `PATH` so that sessions can run `machine-status` by name.

To let agent sessions read the status file, allow reads of
`~/.local/state/machine-status/` in their sandbox configuration if it is not already readable,
and point them at the playbook from your agent instructions, for example with a line such as
"Run `machine-status` before heavy work and follow `~/.local/share/machine-status/PLAYBOOK.md`."

## Configuration

launchd starts each job with its own minimal environment, so a variable set in your shell
does not reach it. Settings for the periodic jobs go in `~/.config/periodic.conf`, a shell
file of assignments that `periodic-run` reads and exports to every job.

```sh
# ~/.config/periodic.conf
PERIODIC_PROJECTS="$HOME/src"          # where to look for repositories, ~/projects by default
PERIODIC_GITHUB_OWNER=my-organization  # whose repositories 310.github checks
PERIODIC_DISK_VOLUMES="/System/Volumes/Data"
PERIODIC_COLLECT="$HOME/src/agent-workstation-admin/scripts/collect.sh"
PERIODIC_RECORD_DIR="$HOME/src/my-machine-record/machine"
```

Settings for the other tools go in the `EnvironmentVariables` dictionary of their LaunchAgent,
followed by a reload with `scripts/install.sh --apply agents`. Each script's header lists every
variable it reads.

| Component | Variables |
|---|---|
| Health Alert | `HEALTH_DISK_WARN_GB`, `HEALTH_DISK_CRIT_GB`, `HEALTH_SWAP_WARN_GB`, `HEALTH_SWAP_CRIT_GB`, `HEALTH_UPTIME_WARN_DAYS`, `HEALTH_REPEAT_SECONDS`, `HEALTH_REPEAT_MAX_SECONDS`, `HEALTH_SMARTCTL`, which may be `off`, and `HEALTH_SMART_DEVICE` |
| machine-status | `MACHINE_STATUS_DIR`, `MACHINE_STATUS_DATA_VOLUME`, `MACHINE_STATUS_SCRATCH_VOLUME`, `MACHINE_STATUS_STALE_SECONDS`, `MACHINE_STATUS_TOP` |
| memwatch | `MEMWATCH_SWAP_MB`, `MEMWATCH_PROC_MB`, `MEMWATCH_DISK_GB`, `MEMWATCH_FREE_PCT`, `MEMWATCH_COOLDOWN_S`, `MEMWATCH_NOTIFY` |
| periodic jobs | `PERIODIC_PROJECTS`, `PERIODIC_STALE_DAYS`, `PERIODIC_MERGED_DAYS`, `PERIODIC_GITHUB_OWNER`, `PERIODIC_DISK_GROWTH_GB`, `PERIODIC_DISK_VOLUMES`, `PERIODIC_HARNESS_FILE_GB`, `PERIODIC_HARNESS_TOTAL_GB`, `PERIODIC_GROWTH_PATH_GB`, `PERIODIC_GROWTH_TOTAL_GB`, `PERIODIC_SIZE_WARN_GB`, `PERIODIC_GROWTH_EXTRA`, `PERIODIC_COLLECT`, `PERIODIC_RECORD_DIR` |
| rotate-logs | `ROTATE_LOGS_CONF`, `ROTATE_PRUNE`, `ROTATE_RECLAIM_DAYS`, `ROTATE_BAK_KEEP`, `ROTATE_BAK_DAYS` |
| collect.sh | `COLLECT_DEST`, `COLLECT_FILES_EXTRA`, `COLLECT_APPS` |
| status line | `STATUSLINE_PROJECT_SEGMENT` |

`rotate-logs` reads the logs to rotate from `~/.config/rotate-logs.conf` when that file exists,
one log a line, giving the full path, the size in kilobytes above which to rotate, and the
number of archives to keep.

```text
/usr/local/var/log/my-service.log 5120 4
```

## Recording configuration

Run the collector from a private repository, then review and commit the result.

```sh
cd ~/src/my-machine-record
COLLECT_DEST="$PWD/machine" sh ~/src/agent-workstation-admin/scripts/collect.sh
git diff
```

Without `COLLECT_DEST` it writes to `./machine` under the current directory, which this
repository ignores, so a collection made here is never published by accident. Its output names
your account, your services and your installed software, so keep it private even after the
secret scan has passed. Set `PERIODIC_COLLECT` and `PERIODIC_RECORD_DIR` and the weekly
`340.config-drift` job reports any difference from the last recorded collection.

## Tests

```sh
./scripts/check.sh                 # the full gate
sh scripts/test-monitors.sh        # Health Alert backoff and the two watchdogs
sh scripts/test-rotate-logs.sh     # rotation, configuration and Agent Mail pruning
sh scripts/test-periodic.sh        # periodic-run's reports, queue, lock and settings
sh scripts/test-collect.sh         # the secret scan, redaction and path checks
```

Each test script exits with its number of failures, uses temporary folders only, and never
notifies, loads a LaunchAgent or touches live state. The gate checks repository hygiene, runs
shellcheck on every shell script and compiles the Python scripts, and on macOS it also lints
the rendered LaunchAgents and runs the four test scripts. Continuous integration runs on
Linux, where the macOS steps are skipped and the gate says so. The readings of memory, swap,
SMART data and uptime come from the live machine and are not covered by the tests.

## Safety

- **Reports only.** The periodic jobs, Health Alert, memwatch and machine-status read and
  report. None of them deletes, upgrades, commits, pushes, stops a process or changes a setting.
- **One documented deletion.** `rotate-logs` truncates the logs it rotates after verifying
  each archive, deletes archives beyond the number kept, and deletes old MCP Agent Mail
  database backups by exact name and age while always keeping the newest twenty-four. Its
  header documents each rule, and `ROTATE_PRUNE=0` turns the pruning off.
- **A dry-run installer.** `scripts/install.sh` changes nothing without `--apply`, backs up
  every file it replaces, never deletes, and uses sudo only in the three system sections.
- **A scanning collector.** `scripts/collect.sh` scans for secret-like strings before writing
  and redacts inline client secrets. The scan recognizes common formats and cannot recognize
  every secret, so review its output before committing it.
- **Shell configuration is code.** `~/.config/periodic.conf` is executed as shell, and the
  status line runs a project's own segment script. Both carry the trust of your shell startup
  files. [`SECURITY.md`](SECURITY.md) lists the trust boundaries.

## Limitations

- The toolkit is specific to macOS. It relies on launchd, `vm_stat`, `memory_pressure`,
  the Berkeley Software Distribution (BSD) forms of `stat` and `df`, `osascript` and the
  Apple File System (APFS) volume layout. It was developed and tested on macOS 27 on Apple
  silicon, with MacPorts. The Homebrew paths have not been tested.
- The session attribution in machine-status and the session inventory read the harnesses'
  private files, such as `~/.claude/sessions/` and `~/.codex/state_5.sqlite`. A harness update
  that changes them can break attribution until the scripts are updated.
- The Agent Mail rotation and pruning in `rotate-logs` matter only if you run an MCP Agent Mail
  server under launchd. They do nothing otherwise.
- Notifications need a logged-in graphical session. A critical alert gives up after nine
  minutes and is left in Notification Center instead, so that an unanswered alert cannot stop
  the checks.

## Uninstall

```sh
for f in ~/Library/LaunchAgents/local.{health-alert,machine-status,memwatch,rotate-logs,periodic.daily,periodic.weekly,periodic.monthly}.plist; do
    launchctl bootout "gui/$(id -u)" "$f" 2>/dev/null
    rm -f "$f"
done
rm -rf ~/Applications/"Health Alert.app" ~/.local/libexec/periodic ~/.local/share/health-alert ~/.local/share/machine-status
cd ~/.local/bin && rm -f health-alert machine-status memwatch periodic-run rotate-logs session-inventory cargo-outdated-check
```

Logs remain in `~/Library/Logs/`, and state in `~/.local/state/` and `~/Library/Caches/local.*`.
Remove any `/etc` file you installed with sudo by hand.

## Development

```sh
./scripts/check.sh                       # the local gate, which continuous integration also runs
scripts/worktree.sh new feat/some-thing  # an isolated worktree for a parallel line
```

The documentation index is [`docs/README.md`](docs/README.md). Agent guidance is in
[`CLAUDE.md`](CLAUDE.md), and [`AGENTS.md`](AGENTS.md) points other assistants to it.
Participation is governed by the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## License

[0BSD](LICENSE).
