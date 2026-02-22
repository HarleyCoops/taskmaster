# Taskmaster

A Codex session-log monitor + same-process continuation wrapper that prevents
premature stopping and emits a deterministic, parseable completion signal.

Codex TUI currently lacks arbitrary writable event hooks
([openai/codex#2109](https://github.com/openai/codex/issues/2109)). Taskmaster
implements equivalent behavior externally by reading
`CODEX_TUI_SESSION_LOG_PATH` and injecting continuation prompts into the same
running Codex process using either tmux transport or expect-PTY transport.

## Behavior

Taskmaster enforces a session-specific done token:

```text
TASKMASTER_DONE::<session_id>
```

When missing at `task_complete`, Taskmaster marks the turn incomplete and can
automatically inject a continuation user message to keep execution going.

Mode selection:
- `TASKMASTER_MODE=auto` (default): prefer tmux if a pane is detected, else
  use expect PTY transport.
- `TASKMASTER_MODE=tmux`: force tmux transport.
- `TASKMASTER_MODE=expect`: force expect PTY transport.

## Install

```bash
bash ~/.codex/skills/taskmaster/install.sh
```

This will:
- Ensure files are present under `~/.codex/skills/taskmaster/`
- Create launcher symlink `~/.codex/bin/codex-taskmaster`

## Run

```bash
codex-taskmaster [codex args]
```

Examples:

```bash
# Run with your normal codex defaults
codex-taskmaster

# Run with a prompt
codex-taskmaster "profile and fix import memory usage"

# Pass codex flags
codex-taskmaster -- --search
```

## Direct Monitor Usage

If you only want read-only monitoring:

```bash
CODEX_TUI_RECORD_SESSION=1 \
CODEX_TUI_SESSION_LOG_PATH=/tmp/codex-session.jsonl \
codex

bash ~/.codex/skills/taskmaster/hooks/check-completion-codex.sh \
  --follow --log /tmp/codex-session.jsonl
```

## Configuration

- `TASKMASTER_DONE_PREFIX` (default `TASKMASTER_DONE`)
  - token format: `<prefix>::<session_id>`
- `TASKMASTER_AUTORESUME` (default `1`)
  - `1`: enable auto-injection when token is missing
  - `0`: disable auto-injection
- `TASKMASTER_AUTORESUME_MAX` (default `0`)
  - `0`: unlimited auto-injections
  - `>0`: max injections before stop
- `TASKMASTER_MAX` (default `0`)
  - monitor warning cap (`0` = unlimited warnings)
- `TASKMASTER_POLL_INTERVAL` (default `0.5`)
  - monitor poll interval (seconds)
- `TASKMASTER_MODE` (default `auto`)
  - `auto`: tmux when available, else expect
  - `tmux`: force tmux transport
  - `expect`: force expect PTY transport
- `TASKMASTER_TMUX_PANE`
  - optional explicit tmux pane id override (example: `%7`)
- `TASKMASTER_LOG_PATH`
  - optional fixed session log path (debugging only)
- `TASKMASTER_EXPECT_PASTE_MODE` (default `bracketed`)
  - `bracketed`: send injected text as bracketed paste, then submit
  - `plain`: send raw text bytes, then submit
- `TASKMASTER_EXPECT_SUBMIT_DELAY_MS` (default `180`)
  - delay before submit key in expect mode (helps avoid paste-burst Enter suppression)

## Uninstall

```bash
bash ~/.codex/skills/taskmaster/uninstall.sh
```

## Notes

- Codex logging needs both variables:
  - `CODEX_TUI_RECORD_SESSION=1`
  - `CODEX_TUI_SESSION_LOG_PATH=<path>`
- The done token is session-specific, so automation can parse completion deterministically.
- For details, see `docs/SPEC.md`.

## Requirements

- Codex CLI
- `jq`
- `bash`
- `tmux` (for tmux transport)
- `expect` (for non-tmux same-process transport)

## License

MIT
