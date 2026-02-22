# Taskmaster

Taskmaster is a completion guard for coding agents.

It addresses a common failure mode: the agent makes partial progress, writes a
summary, and stops before the user goal is actually finished.

## Core Contract

A run is complete only when the assistant emits:

```text
TASKMASTER_DONE::<session_id>
```

If that token is missing at stop time, Taskmaster blocks stop and pushes the
session to continue.

## How It Works

- Codex path:
  - Runs through a wrapper (`codex` shim / `codex-taskmaster` launcher).
  - Enables Codex session logs.
  - Watches `task_complete` / `turn_complete` events.
  - If done token is missing, injects a continuation prompt into the same
    running Codex process via expect PTY.
- Claude path:
  - Registers a `Stop` command hook.
  - Hook runs `check-completion.sh`.
  - If done token is missing, the stop is blocked with corrective feedback.

## Install

```bash
bash ~/.codex/skills/taskmaster/install.sh
```

Auto-detection behavior:
- Installs Codex integration when `codex` or `~/.codex` exists.
- Installs Claude integration when `claude` or `~/.claude` exists.
- If both are present, installs both.
- If neither is detected, defaults to both.

Optional target override:

```bash
TASKMASTER_INSTALL_TARGET=codex bash ~/.codex/skills/taskmaster/install.sh
TASKMASTER_INSTALL_TARGET=claude bash ~/.codex/skills/taskmaster/install.sh
TASKMASTER_INSTALL_TARGET=both bash ~/.codex/skills/taskmaster/install.sh
```

Installed artifacts:
- Codex:
  - `~/.codex/skills/taskmaster/`
  - `~/.codex/bin/codex-taskmaster`
  - `~/.codex/bin/codex` (shim to Taskmaster wrapper)
- Claude:
  - `~/.claude/skills/taskmaster/`
  - `~/.claude/hooks/taskmaster-check-completion.sh`
  - Stop-hook entry added to `~/.claude/settings.json`

## Usage

### Codex

Run normally:

```bash
codex [args]
```

Explicit alias is also available:

```bash
codex-taskmaster [args]
```

### Claude

Run Claude normally after install. Taskmaster hook enforcement is automatic.

## Monitor-Only Mode (Codex)

Use this if you only want read-only completion checks:

```bash
CODEX_TUI_RECORD_SESSION=1 \
CODEX_TUI_SESSION_LOG_PATH=/tmp/codex-session.jsonl \
codex

bash ~/.codex/skills/taskmaster/hooks/check-completion-codex.sh \
  --follow --log /tmp/codex-session.jsonl
```

## Configuration

- `TASKMASTER_MAX` (default `0`):
  - Limits warning count in monitors.
  - `0` means unlimited warnings.

## Uninstall

```bash
bash ~/.codex/skills/taskmaster/uninstall.sh
```

Auto-detection behavior mirrors install and removes Taskmaster from detected
Codex/Claude environments.

Optional target override:

```bash
TASKMASTER_UNINSTALL_TARGET=codex bash ~/.codex/skills/taskmaster/uninstall.sh
TASKMASTER_UNINSTALL_TARGET=claude bash ~/.codex/skills/taskmaster/uninstall.sh
TASKMASTER_UNINSTALL_TARGET=both bash ~/.codex/skills/taskmaster/uninstall.sh
```

## Requirements

- `bash`
- `jq`
- Codex integration:
  - Codex CLI
  - `expect`
- Claude integration:
  - Claude Code with `Stop` hooks enabled
  - `python3` (for install/uninstall settings updates)

## License

MIT
