# Taskmaster
## Product & Technical Specification

**Version**: 4.1.0  
**Scope**:
- `taskmaster/hooks/check-completion-codex.sh`
- `taskmaster/hooks/inject-continue-codex-tmux.sh`
- `taskmaster/hooks/run-codex-expect-bridge.exp`
- `taskmaster/run-taskmaster-codex.sh`
- `taskmaster/SKILL.md`

## 1. Goal

Prevent premature agent stopping and provide a deterministic, machine-parseable
completion signal.

Codex TUI currently has no arbitrary writable stop hook surface
([openai/codex#2109](https://github.com/openai/codex/issues/2109)). Taskmaster
uses session-log polling to enforce the same completion contract externally.

## 2. Completion Contract

A run is considered complete only when assistant output includes:

```text
TASKMASTER_DONE::<session_id>
```

- `<session_id>` comes from `session_configured` in TUI session logs.
- The line must be emitted by the agent only when work is truly complete.
- External systems can parse this line as the authoritative completion marker.

## 3. Architecture

### 3.1 Codex Session Logging

Taskmaster requires:

- `CODEX_TUI_RECORD_SESSION=1`
- `CODEX_TUI_SESSION_LOG_PATH=/path/to/session.jsonl`

Log format source:
- `codex-rs/tui/src/session_log.rs` (`kind`, `dir`, `payload` envelope)
- `codex-rs/protocol/src/protocol.rs` (`task_complete`, `session_configured`)

### 3.2 Monitor Script (`hooks/check-completion-codex.sh`)

The monitor is read-only and parses JSONL events.

Decision flow:

1. Capture `session_id` from `kind=codex_event` + `msg.type=session_configured`.
2. On each `task_complete`, inspect `last_agent_message`.
3. If done token is missing, emit a warning.
4. On `session_end`, exit:
   - `0` when token was found
   - `2` when token missing
   - `3` when no `task_complete` events were observed

### 3.3 Continuation Wrapper (`run-taskmaster-codex.sh`)

Wrapper behavior:

1. Starts Codex with session logging enabled.
2. Selects same-process transport:
   - tmux pane injector, or
   - expect PTY bridge with file-queue injector.
3. If completion token is missing and auto-resume is enabled:
   - injects a new user message into the same pane/process
4. Continues until completion token is emitted or injection cap is reached.

### 3.4 Same-Process Injector (`hooks/inject-continue-codex-tmux.sh`)

Injector behavior:

1. Follows the active session log for `task_complete`/`turn_complete`.
2. For each completed turn without done token:
   - builds continuation prompt
   - injects prompt into target pane with `tmux paste-buffer` + `send-keys Enter`
3. Uses turn-id/signature dedupe to avoid duplicate injection on re-read.

### 3.5 Expect PTY Bridge (`hooks/run-codex-expect-bridge.exp`)

Bridge behavior:

1. Spawns Codex inside a managed PTY.
2. Polls queue files emitted by injector (`inject.*.txt`).
3. Sends queued prompt text into the same running Codex PTY using bracketed
   paste framing by default, then submits with Enter after a short delay.
4. Supports env-tunable fallback to raw byte paste mode.

## 4. Runtime Interfaces

### 4.1 Monitor Inputs

- `--log <path>` or `CODEX_TUI_SESSION_LOG_PATH`
- `--follow` (optional)
- `TASKMASTER_DONE_PREFIX`
- `TASKMASTER_MAX`
- `TASKMASTER_POLL_INTERVAL`

### 4.2 Monitor Exit Codes

- `0`: token found
- `2`: incomplete (token missing)
- `3`: no `task_complete` observed
- `4`: invalid usage / missing prerequisites

## 5. Configuration

- `TASKMASTER_DONE_PREFIX` (default `TASKMASTER_DONE`)
- `TASKMASTER_AUTORESUME` (default `1`)
- `TASKMASTER_AUTORESUME_MAX` (default `0` = unlimited)
- `TASKMASTER_MAX` (warning cap for monitor)
- `TASKMASTER_POLL_INTERVAL` (default `0.5` seconds)
- `TASKMASTER_MODE` (`auto`, `tmux`, `expect`)
- `TASKMASTER_TMUX_PANE` (optional explicit target pane)
- `TASKMASTER_LOG_PATH` (optional fixed log path)
- `TASKMASTER_EXPECT_PASTE_MODE` (`bracketed` or `plain`)
- `TASKMASTER_EXPECT_SUBMIT_DELAY_MS` (delay before Enter in expect mode)

## 6. Operational Notes

- This is not a native stop hook; it is external control-plane logic.
- In tmux/expect modes, injection is same-process (new user message into current process).
- For strict CI-style checks, run monitor in analyze mode and require exit `0`.
