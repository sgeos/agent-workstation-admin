# Changelog

All notable changes are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The repository, seeded from `sgeos/project-template` at `8a7962236da7c15210da4b62023b82818a7af08d`, release `v1.0.9`.
- The first public cut of the toolkit, generalized from one workstation's private
  configuration. It holds Health Alert with its applet, `machine-status` and its
  playbook, `memwatch`, `periodic-run` with two daily and six weekly report jobs,
  `rotate-logs`, `session-inventory`, `cargo-outdated-check`, a Claude Code status line,
  the LaunchAgent and `/etc` templates, `scripts/install.sh`, `scripts/collect.sh` and four
  test scripts.
- Settings that were fixed on the original machine are now configurable, among them the
  GitHub owner, the measured volumes, the record that the drift report compares with, the
  logs that `rotate-logs` rotates, and the location of `smartctl`.

### Fixed

- `periodic-run` now exports the settings in `periodic.conf`, which the jobs, as separate
  processes, did not otherwise see.
- `machine-status --help` now prints the `sample` usage line as well.
- The `rotate-logs` tests no longer prune the real Agent Mail folders of the machine that
  runs them.

