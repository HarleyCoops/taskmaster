#!/usr/bin/env bash
#
# Codex Taskmaster same-process injector for tmux sessions.
# Watches a Codex session log and, on each incomplete task_complete/turn_complete,
# injects a continuation prompt into the same tmux pane.
#
# Exit codes:
#   0 = at least one done token observed
#   2 = completion(s) observed but no done token
#   3 = no completion events observed
#   4 = invalid usage / prerequisites
#
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  inject-continue-codex-tmux.sh --log <session_log.jsonl> [--pane <tmux_pane_id>] [--emit-dir <dir>] [--follow]

Options:
  --log <path>          Path to CODEX_TUI_SESSION_LOG_PATH file.
  --pane <pane_id>      tmux target pane id (for example: %3).
  --emit-dir <dir>      Emit injection prompts as files in <dir> (non-tmux mode).
  --follow              Follow live updates until session_end.
  --quiet               Suppress non-error output.
  --done-prefix <text>  Done token prefix (default: TASKMASTER_DONE).
  --poll-interval <n>   Poll interval in seconds (default: 0.5).
  --max-injections <n>  Max auto-injections (0 = unlimited).
  -h, --help            Show help.
USAGE
}

LOG_PATH="${CODEX_TUI_SESSION_LOG_PATH:-}"
PANE="${TASKMASTER_TMUX_PANE:-${TMUX_PANE:-}}"
EMIT_DIR=""
FOLLOW=0
QUIET=0
DONE_PREFIX="${TASKMASTER_DONE_PREFIX:-TASKMASTER_DONE}"
POLL_INTERVAL="${TASKMASTER_POLL_INTERVAL:-0.5}"
MAX_INJECTIONS="${TASKMASTER_AUTORESUME_MAX:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      LOG_PATH="${2:-}"
      shift 2
      ;;
    --pane)
      PANE="${2:-}"
      shift 2
      ;;
    --emit-dir)
      EMIT_DIR="${2:-}"
      shift 2
      ;;
    --follow)
      FOLLOW=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    --done-prefix)
      DONE_PREFIX="${2:-}"
      shift 2
      ;;
    --poll-interval)
      POLL_INTERVAL="${2:-}"
      shift 2
      ;;
    --max-injections)
      MAX_INJECTIONS="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 4
      ;;
  esac
done

if [[ -z "$LOG_PATH" ]]; then
  echo "Missing --log (or CODEX_TUI_SESSION_LOG_PATH)." >&2
  exit 4
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 4
fi

if [[ -n "$EMIT_DIR" ]]; then
  mkdir -p "$EMIT_DIR"
else
  if [[ -z "$PANE" ]]; then
    echo "Missing --pane (or TMUX_PANE/TASKMASTER_TMUX_PANE)." >&2
    exit 4
  fi

  if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux is required for pane injection mode." >&2
    exit 4
  fi

  if ! tmux list-panes -a -F '#{pane_id}' | grep -Fxq "$PANE"; then
    echo "tmux pane not found: $PANE" >&2
    exit 4
  fi
fi

SESSION_ID=""
DONE_FOUND=0
SESSION_ENDED=0
TASK_COMPLETE_COUNT=0
INJECTION_COUNT=0
LAST_HANDLED_TURN_ID=""
LAST_HANDLED_SIG=""

build_reprompt() {
  local sid="$1"
  local token

  if [[ -n "$sid" && "$sid" != "null" ]]; then
    token="${DONE_PREFIX}::${sid}"
  else
    token="${DONE_PREFIX}::<session_id>"
  fi

  cat <<RE-PROMPT
TASKMASTER: your previous turn ended without the required completion token.

Re-read the user's latest request and continue executing work immediately.
Do not stop after analysis. Implement, verify, and then report results.

When and only when everything is genuinely complete, include this exact line
on its own line in your final response:
$token
RE-PROMPT
}

is_done_text() {
  local text="$1"
  [[ -n "$text" ]] || return 1

  if [[ -n "$SESSION_ID" ]]; then
    [[ "$text" == *"${DONE_PREFIX}::${SESSION_ID}"* ]]
  else
    [[ "$text" == *"${DONE_PREFIX}::"* ]]
  fi
}

inject_prompt() {
  local turn_id="$1"
  local sid_for_prompt="$2"
  local buffer_name="taskmaster-inject-$$"
  local prompt_file=""
  local prompt

  if [[ "$MAX_INJECTIONS" -gt 0 && "$INJECTION_COUNT" -ge "$MAX_INJECTIONS" ]]; then
    [[ "$QUIET" -eq 1 ]] || echo "[TASKMASTER] injection limit reached (${INJECTION_COUNT}/${MAX_INJECTIONS}); no further auto-injections." >&2
    return 0
  fi

  prompt="$(build_reprompt "$sid_for_prompt")"

  if [[ -n "$EMIT_DIR" ]]; then
    prompt_file="$(mktemp "$EMIT_DIR/inject.XXXXXX")"
    mv "$prompt_file" "$prompt_file.txt"
    prompt_file="$prompt_file.txt"
    printf '%s' "$prompt" > "$prompt_file"
  else
    tmux set-buffer -b "$buffer_name" -- "$prompt"
    tmux paste-buffer -t "$PANE" -b "$buffer_name"
    tmux delete-buffer -b "$buffer_name" >/dev/null 2>&1 || true
    tmux send-keys -t "$PANE" Enter
  fi

  INJECTION_COUNT=$((INJECTION_COUNT + 1))
  if [[ "$QUIET" -eq 0 ]]; then
    if [[ -n "$EMIT_DIR" ]]; then
      echo "[TASKMASTER] queued continuation prompt for turn ${turn_id:-<unknown>} (count=${INJECTION_COUNT}, file=${prompt_file})." >&2
    else
      echo "[TASKMASTER] auto-injected continuation prompt for turn ${turn_id:-<unknown>} (count=${INJECTION_COUNT})." >&2
    fi
  fi
}

process_line() {
  local line="$1"
  [[ -n "$line" ]] || return

  local kind msg_type sid turn_id msg_text sig

  kind="$(jq -Rr 'fromjson? | .kind // empty' <<<"$line" 2>/dev/null || true)"
  [[ -n "$kind" ]] || return

  case "$kind" in
    codex_event)
      msg_type="$(jq -Rr 'fromjson? | .payload.msg.type // empty' <<<"$line" 2>/dev/null || true)"
      case "$msg_type" in
        session_configured)
          sid="$(jq -Rr 'fromjson? | .payload.msg.session_id // empty' <<<"$line" 2>/dev/null || true)"
          if [[ -n "$sid" && "$sid" != "null" ]]; then
            SESSION_ID="$sid"
            [[ "$QUIET" -eq 1 ]] || echo "[TASKMASTER] attached to session $SESSION_ID on pane $PANE" >&2
          fi
          ;;
        task_complete|turn_complete)
          TASK_COMPLETE_COUNT=$((TASK_COMPLETE_COUNT + 1))
          turn_id="$(jq -Rr 'fromjson? | .payload.msg.turn_id // empty' <<<"$line" 2>/dev/null || true)"
          msg_text="$(jq -Rr 'fromjson? | .payload.msg.last_agent_message // ""' <<<"$line" 2>/dev/null || true)"

          if [[ -n "$turn_id" && "$turn_id" == "$LAST_HANDLED_TURN_ID" ]]; then
            return
          fi

          if [[ -z "$turn_id" ]]; then
            sig="$(printf '%s' "$msg_text" | cksum | awk '{print $1":"$2}')"
            if [[ -n "$sig" && "$sig" == "$LAST_HANDLED_SIG" ]]; then
              return
            fi
            LAST_HANDLED_SIG="$sig"
          else
            LAST_HANDLED_TURN_ID="$turn_id"
          fi

          if is_done_text "$msg_text"; then
            DONE_FOUND=1
            [[ "$QUIET" -eq 1 ]] || echo "[TASKMASTER] done token detected; no injection for turn ${turn_id:-<unknown>}." >&2
          else
            inject_prompt "$turn_id" "$SESSION_ID"
          fi
          ;;
      esac
      ;;
    session_end)
      SESSION_ENDED=1
      ;;
  esac
}

process_chunk() {
  local chunk="$1"
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    process_line "$line"
  done <<<"$chunk"
}

if [[ "$FOLLOW" -eq 1 ]]; then
  while [[ ! -f "$LOG_PATH" ]]; do
    sleep "$POLL_INTERVAL"
  done
elif [[ ! -f "$LOG_PATH" ]]; then
  echo "Log path does not exist: $LOG_PATH" >&2
  exit 4
fi

OFFSET=0
while true; do
  if [[ ! -f "$LOG_PATH" ]]; then
    if [[ "$FOLLOW" -eq 1 ]]; then
      sleep "$POLL_INTERVAL"
      continue
    fi
    echo "Log path does not exist: $LOG_PATH" >&2
    exit 4
  fi

  local_size="$(wc -c <"$LOG_PATH" 2>/dev/null || echo 0)"
  if [[ "$local_size" -lt "$OFFSET" ]]; then
    OFFSET=0
  fi

  if [[ "$local_size" -gt "$OFFSET" ]]; then
    chunk="$(tail -c +"$((OFFSET + 1))" "$LOG_PATH" 2>/dev/null || true)"
    process_chunk "$chunk"
    OFFSET="$local_size"
  fi

  if [[ "$FOLLOW" -eq 0 ]]; then
    break
  fi

  if [[ "$SESSION_ENDED" -eq 1 ]]; then
    break
  fi

  sleep "$POLL_INTERVAL"
done

if [[ "$DONE_FOUND" -eq 1 ]]; then
  exit 0
fi

if [[ "$TASK_COMPLETE_COUNT" -eq 0 ]]; then
  exit 3
fi

exit 2
