---
name: taskmaster
description: |
  Codex session-log monitor plus same-process injector (tmux or expect PTY)
  that keeps work moving until an explicit parseable done signal is emitted.
author: blader
version: 4.1.0
---

# Taskmaster

Taskmaster for Codex uses session-log polling plus automatic continuation.
Codex TUI does not currently expose arbitrary writable stop hooks, so this
skill implements the same completion contract externally.

## How It Works

1. **Run Codex via wrapper**: `run-taskmaster-codex.sh` sets
   `CODEX_TUI_RECORD_SESSION=1` and a log path.
2. **Monitor parses log events** and checks completion on each
   `task_complete` event.
3. **Parseable token contract**:
   `TASKMASTER_DONE::<session_id>`
4. **Token missing**:
   - inject follow-up user message into the same running process via:
     - `tmux send-keys` transport, or
     - `expect` PTY bridge transport outside tmux
5. **Token present**: no further injection.

## Parseable Done Signal

When the work is genuinely complete, the agent must include this exact line
in its final response (on its own line):

```text
TASKMASTER_DONE::<session_id>
```

This gives external automation a deterministic completion marker to parse.

## Configuration

- `TASKMASTER_MAX` (default `0`): max warning count before suppression in the
  monitor. `0` means unlimited warnings.
- `TASKMASTER_DONE_PREFIX` (default `TASKMASTER_DONE`): Prefix used for the
  done token.
- `TASKMASTER_AUTORESUME` (default `1`): enable automatic continuation
  injection when completion token is missing.
- `TASKMASTER_AUTORESUME_MAX` (default `0`): max automatic injections.
  `0` means unlimited.
- `TASKMASTER_POLL_INTERVAL` (default `0.5`): monitor polling interval.
- `TASKMASTER_MODE` (default `auto`): `auto`, `tmux`, or `expect`.
- `TASKMASTER_TMUX_PANE`: optional explicit tmux pane target.
- `TASKMASTER_LOG_PATH`: optional fixed log path (debugging only).
- `TASKMASTER_EXPECT_PASTE_MODE` (default `bracketed`): expect transport
  payload mode (`bracketed` or `plain`).
- `TASKMASTER_EXPECT_SUBMIT_DELAY_MS` (default `180`): expect transport
  delay before Enter submit.

## Setup

Install and run:

```bash
bash ~/.codex/skills/taskmaster/install.sh
codex-taskmaster
```

## Disabling

Set `TASKMASTER_AUTORESUME=0` or run plain `codex` directly.
