# Handoff

> **Navigation**: [Process](./README.md) | [Documentation Root](../README.md)

This is a state file. It is overwritten whole on every update and holds only what is in
flight, why, what is owed and the next step, within a budget of 8 KB. History lives in
git. A rewrite that drops an open item says in its commit message whether the item was
completed, moved or abandoned.

## State on 2026-11-24

- **First cut.** The toolkit was assembled locally from one workstation's private
  configuration and generalized for public use. It has one commit on `main` and no remote.

## Next step

The operator reviews the tree, creates the GitHub repository, adds the remote and pushes.

## Open

- The repository has no remote yet. Creating it, applying the repository settings and the
  ruleset, and making it public are the operator's actions.
- Before it is made public, run `scripts/check.sh --history --hygiene-only` with the terms
  list in place, and a credential scanner such as `gitleaks git` over the history.
- The Homebrew paths in `320.updates`, `collect.sh` and `health-alert` were written without
  a Homebrew installation to test against.

## Environment

The first cut was assembled and tested on macOS 27 on Apple silicon, with MacPorts.

## Validity

```sh
git status --short          # clean
git log --oneline -5        # the newest commit should describe this state
./scripts/check.sh          # exits zero
```

Report any check not run, and any commit after the one that last rewrote this file.

## Mailbox

None assigned.
