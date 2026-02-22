# Taskmaster

A completion gate for coding agents. Taskmaster blocks premature stop and
enforces a deterministic, parseable completion signal.

## Intention

Most agent runs fail in a predictable way: the model makes partial progress,
summarizes, and stops before the user goal is actually complete. Taskmaster is
designed to close that gap.

The goal is simple:
- force explicit completion instead of implied completion
- keep the same live session moving when work is incomplete
- make completion machine-verifiable for automation and tooling

## Solution

Taskmaster enforces one contract across both agents:
- Completion must include a session-scoped token:

```text
TASKMASTER_DONE::<session_id>
```

If the token is missing at stop time, Taskmaster blocks stop and forces another
execution loop.

Supported modes:
- Codex CLI: session-log monitor + same-process continuation via expect PTY.
- Claude Code: native `Stop` hook command using `check-completion.sh`.

## Behavior

Taskmaster enforces a session-specific done token:

```text
TASKMASTER_DONE::<session_id>
```

If that token is missing when the agent tries to stop, Taskmaster blocks stop.

## Prompting Model

Taskmaster uses corrective continuation prompts with a strict intention:
- re-anchor the model to the original user goal
- require implementation + verification before stop
- forbid premature done-token emission

In Codex mode, continuation prompts are injected into the same running process
through the expect bridge. In Claude mode, the Stop hook blocks stop and
returns the corrective prompt as hook feedback.

## Install

```bash
bash ~/.codex/skills/taskmaster/install.sh
```

`install.sh` auto-detects your environment and installs for:
- Codex when `codex` or `~/.codex` is present
- Claude when `claude` or `~/.claude` is present
- Both when both are detected

If neither is detected, it defaults to installing both.

Override target selection with:

```bash
TASKMASTER_INSTALL_TARGET=codex bash ~/.codex/skills/taskmaster/install.sh
TASKMASTER_INSTALL_TARGET=claude bash ~/.codex/skills/taskmaster/install.sh
TASKMASTER_INSTALL_TARGET=both bash ~/.codex/skills/taskmaster/install.sh
```

What gets installed:
- Codex:
  - `~/.codex/skills/taskmaster/`
  - `~/.codex/bin/codex-taskmaster`
  - `~/.codex/bin/codex` (shim to Taskmaster wrapper)
- Claude:
  - `~/.claude/skills/taskmaster/`
  - `~/.claude/hooks/taskmaster-check-completion.sh`
  - Stop hook registration in `~/.claude/settings.json`

## Codex Usage

```bash
codex [codex args]
```

`codex-taskmaster` remains available as an explicit alias.

## Claude Usage

After install, the Stop hook is configured automatically. Run Claude normally.

## Codex Direct Monitor Usage

If you only want read-only monitoring:

```bash
CODEX_TUI_RECORD_SESSION=1 \
CODEX_TUI_SESSION_LOG_PATH=/tmp/codex-session.jsonl \
codex

bash ~/.codex/skills/taskmaster/hooks/check-completion-codex.sh \
  --follow --log /tmp/codex-session.jsonl
```

## Configuration

- `TASKMASTER_MAX` (default `0`)
  - warning cap (`0` = unlimited warnings)

## Uninstall

```bash
bash ~/.codex/skills/taskmaster/uninstall.sh
```

`uninstall.sh` auto-detects Codex/Claude and removes Taskmaster from whichever
is present.

Override target selection with:

```bash
TASKMASTER_UNINSTALL_TARGET=codex bash ~/.codex/skills/taskmaster/uninstall.sh
TASKMASTER_UNINSTALL_TARGET=claude bash ~/.codex/skills/taskmaster/uninstall.sh
TASKMASTER_UNINSTALL_TARGET=both bash ~/.codex/skills/taskmaster/uninstall.sh
```

## Requirements

- `jq`
- `bash`
- Codex mode:
  - Codex CLI
  - `expect`
- Claude mode:
  - Claude Code with `Stop` hooks enabled
  - `python3` (used by install/uninstall to update `settings.json`)

## License

MIT
