#!/usr/bin/env bash
#
# Codex Taskmaster same-process injector (queue-emitter mode).
# Watches a Codex session log and, on each incomplete task_complete/turn_complete,
# writes a continuation prompt file into the expect bridge queue.
#
# Exit codes:
#   0 = at least one done token observed
#   2 = completion(s) observed but no done token
#   3 = no completion events observed
#   4 = invalid usage / prerequisites
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../taskmaster-compliance-prompt.sh"

usage() {
  cat <<'USAGE'
Usage:
  inject-continue-codex.sh --log <session_log.jsonl> --emit-dir <dir> [--follow] [--quiet]

Options:
  --log <path>      Path to CODEX_TUI_SESSION_LOG_PATH file.
  --emit-dir <dir>  Emit injection prompts as files in <dir>.
  --follow          Follow live updates until session_end.
  --quiet           Suppress non-error output.
  -h, --help        Show help.
USAGE
}

LOG_PATH="${CODEX_TUI_SESSION_LOG_PATH:-}"
EMIT_DIR=""
FOLLOW=0
QUIET=0
DONE_PREFIX="TASKMASTER_DONE"
POLL_INTERVAL="1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      LOG_PATH="${2:-}"
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

if [[ -z "$EMIT_DIR" ]]; then
  echo "Missing --emit-dir." >&2
  exit 4
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 4
fi

mkdir -p "$EMIT_DIR"

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
  local shared_prompt

  if [[ -n "$sid" && "$sid" != "null" ]]; then
    token="${DONE_PREFIX}::${sid}"
  else
    token="${DONE_PREFIX}::<session_id>"
  fi

  shared_prompt="$(build_taskmaster_compliance_prompt "$token")"

  cat <<RE-PROMPT
TASKMASTER: Stop is blocked until completion is explicitly confirmed.

${shared_prompt}
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
  local prompt_file
  local prompt

  prompt="$(build_reprompt "$sid_for_prompt")"

  prompt_file="$(mktemp "$EMIT_DIR/inject.XXXXXX")"
  mv "$prompt_file" "$prompt_file.txt"
  prompt_file="$prompt_file.txt"
  printf '%s' "$prompt" > "$prompt_file"

  INJECTION_COUNT=$((INJECTION_COUNT + 1))
  if [[ "$QUIET" -eq 0 ]]; then
    echo "[TASKMASTER] queued continuation prompt for turn ${turn_id:-<unknown>} (count=${INJECTION_COUNT}, file=${prompt_file})." >&2
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
            [[ "$QUIET" -eq 1 ]] || echo "[TASKMASTER] attached to session $SESSION_ID" >&2
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
