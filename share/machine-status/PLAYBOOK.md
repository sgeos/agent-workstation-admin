# Shared-machine resource playbook

This machine is shared by many agent sessions and by the operator. Any of them, doing anything,
can exhaust memory, swap, disk or processor time. This playbook says how every session should
behave, whatever the work is. It names no activity on purpose, because the next shortage will
come from somewhere new.

Whoever administers the machine owns system-wide monitoring. The sessions working on each project
own that project's tooling and decide how to apply this playbook to it.

## Observe

- Run `machine-status` before starting work whose footprint is large or unknown, and from time to
  time during long work. It works inside agent sandboxes. Its exit status is 0 for ok, 1 for
  elevated, 2 for critical and 3 for stale or missing. `machine-status --level` prints only the
  level.
- Find yourself in its session and process tables. Know whether you are part of the problem.
- Treat stale or missing status as elevated, and say so in your report.

## Act on your own work only

| Level | What to do |
|---|---|
| ok | Proceed. Where your footprint is unknown, start small and measure before widening. |
| elevated | Start nothing heavy that is new. If you are among the largest consumers, reduce your own load. |
| critical | Start nothing new. If you are among the largest consumers, wind your own load down now, preserving the work. Report to the operator at once. |

- Act only on processes you started. Never signal, stop or alter another session's work, and never
  ask another session to act on yours or on a third party's.
- Prefer actions that keep the work and can be undone, such as waiting, pausing and lowering
  parallelism, over actions that lose it, such as killing. Killing work is the operator's decision.
- Leave the system's own processes, and the operator's applications, alone. Mention them if they
  are the cause.

## Report

- Tell the operator what you saw, with the level and figures, what you did, and what you could not
  do.
- If your own permission settings refuse an action you need, report that. Do not route the action
  through another session.
- Resume normal work only when the level is ok again.

## Learn

- Measure the peak footprint of heavy work when you can, and record it where your project keeps its
  notes, so later runs can plan from data rather than guesses.
- After an incident, improve what sessions can see before adding a limit on what they may run.
