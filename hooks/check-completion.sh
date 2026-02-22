#!/usr/bin/env bash
#
# Stop hook: keep firing until the agent emits an explicit done signal.
#
# The stop is allowed only after the transcript contains:
#   TASKMASTER_DONE::<session_id>
#
# Optional env vars:
#   TASKMASTER_MAX          Max number of blocks before allowing stop (default: 0 = infinite)
#   TASKMASTER_DONE_PREFIX  Prefix for done token (default: TASKMASTER_DONE)
#
set -u

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ]; then
  SESSION_ID="unknown-session"
fi

# --- skip subagents: they have very short transcripts ---
if [ -f "$TRANSCRIPT" ]; then
  LINE_COUNT=$(wc -l < "$TRANSCRIPT" 2>/dev/null || echo "0")
  if [ "$LINE_COUNT" -lt 20 ]; then
    exit 0
  fi
fi

# --- counter ---
COUNTER_DIR="${TMPDIR:-/tmp}/taskmaster"
mkdir -p "$COUNTER_DIR"
COUNTER_FILE="${COUNTER_DIR}/${SESSION_ID}"
MAX=${TASKMASTER_MAX:-0}

COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
fi

# --- done signal detection ---
DONE_PREFIX="${TASKMASTER_DONE_PREFIX:-TASKMASTER_DONE}"
DONE_SIGNAL="${DONE_PREFIX}::${SESSION_ID}"
HAS_DONE_SIGNAL=false
HAS_RECENT_ERRORS=false

# Primary: check last_assistant_message (most reliable — no transcript parsing needed)
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if [ -n "$LAST_MSG" ] && echo "$LAST_MSG" | grep -Fq "$DONE_SIGNAL" 2>/dev/null; then
  HAS_DONE_SIGNAL=true
fi


# Fallback: check transcript file if last_assistant_message didn't match
if [ "$HAS_DONE_SIGNAL" = false ] && [ -f "$TRANSCRIPT" ]; then
  # Use grep directly on file (avoids broken-pipe with echo|grep under pipefail)
  if tail -400 "$TRANSCRIPT" 2>/dev/null | grep -Fq "$DONE_SIGNAL"; then
    HAS_DONE_SIGNAL=true
  fi

  if tail -40 "$TRANSCRIPT" 2>/dev/null | grep -qi '"is_error":\s*true'; then
    HAS_RECENT_ERRORS=true
  fi
fi

if [ "$HAS_DONE_SIGNAL" = true ]; then
  rm -f "$COUNTER_FILE"
  exit 0
fi

NEXT=$((COUNT + 1))
echo "$NEXT" > "$COUNTER_FILE"

# Optional escape hatch. Default is infinite (0) so hook keeps firing.
if [ "$MAX" -gt 0 ] && [ "$NEXT" -ge "$MAX" ]; then
  rm -f "$COUNTER_FILE"
  exit 0
fi

if [ "$HAS_RECENT_ERRORS" = true ]; then
  PREAMBLE="Recent tool errors were detected. Resolve them before declaring done."
else
  PREAMBLE="Stop is blocked until completion is explicitly confirmed."
fi

if [ "$MAX" -gt 0 ]; then
  LABEL="TASKMASTER (${NEXT}/${MAX})"
else
  LABEL="TASKMASTER (${NEXT})"
fi

# --- reprompt ---
REASON="${LABEL}: ${PREAMBLE}

Before stopping, do each of these checks:

1. GOAL CONFRONTATION (do this FIRST — before any other check). Answer these questions explicitly in your response. Do not skip or rephrase them:
   a. What is the user's stated goal or success criterion? Write it out verbatim.
   b. Is it achieved RIGHT NOW? Answer \"yes\" or \"no\". Not \"partially\", not \"mostly\", not \"significant progress was made\". Yes or no.
   c. If no: you are NOT DONE. Do not proceed to emit the done signal. Go do more work. The ONLY exception is if the user explicitly told you to stop or deprioritized the goal. There is no other valid reason to stop. Not \"hard technical constraint\", not \"tried N approaches\" — if the goal is not met and the user has not told you to stop, keep working.
   \"Diminishing returns\", \"distributed profile\", \"no single dominant hotspot\", \"would require broader architectural changes\", or any variation of \"I made good progress\" are NOT valid reasons to stop. These are rationalizations. The user asked for the goal, not for progress toward it.

2. RE-READ THE ORIGINAL USER MESSAGE(S). List every discrete request or acceptance criterion. For each one, confirm it is fully addressed — not just started, FULLY done. If the user explicitly changed their mind, withdrew a request, or told you to stop or skip something, treat that item as resolved and do NOT continue working on it.
3. CHECK THE TASK LIST. Review every task. Any task not marked completed? Do it now — unless the user indicated it is no longer wanted.
4. CHECK THE PLAN. Walk through each step — INCLUDING verification steps. Any step skipped or partially done? Finish it — unless the user redirected or deprioritized it. If the plan includes ANY verification steps (builds, tests, lints, type-checks, manual validation, smoke tests, functional tests, or any other form of verification), you MUST actually execute them and see them pass — do not skip them or just claim they pass.
5. CHECK FOR ERRORS OR INCOMPLETE WORK. Did anything fail or remain unfinished? Fix it. This applies to ALL types of problems — logic errors, missing functionality, incomplete refactors, broken scripts, configuration issues, or anything else that prevents the work from being fully done.
6. CHECK FOR LOOSE ENDS. Any TODO comments, placeholder code, missing tests, untested changes, or follow-ups noted but not acted on?
7. CHECK FOR BLOCKERS. If something is blocking you, do NOT give up. You are a world-class engineer with access to a full development environment, a terminal, every tool you need, and all the information on the internet. If it does not violate the laws of physics, it is within your ability to solve it. Try a different approach, read more code, search for examples, re-examine your assumptions. Never declare something a blocker and stop. Solve it. This includes pre-existing bugs, broken tests, missing data, infrastructure issues, or anything else in the environment that prevents your work from being validated. \"I didn't cause this bug\" is not an excuse to stop — if it blocks your task, fix it. You own the outcome, not just your diff.

IMPORTANT: The user's latest instructions always take priority. If the user said to stop, move on, or skip something, respect that — do not force completion of work the user no longer wants.

DO NOT NARRATE — EXECUTE: If any incomplete work remains, your ONLY job is to DO that work right now. Do NOT respond by explaining what the remaining tasks are, describing their complexity, listing their dependencies, or analyzing how difficult they will be. Do NOT ask the user for permission or direction to proceed. Do NOT write summaries of what is left. Just DO the work. The user asked you to do it — that IS your direction. Every sentence you spend describing remaining work instead of doing it is wasted. Open files, write code, run commands, fix bugs. Act.

PROGRESS IS NOT COMPLETION: Making progress toward a goal is not the same as achieving it. \"I improved X from 1345ms to 866ms\" does not satisfy a goal of \"<500ms\". Describing remaining work with phrases like \"would require deeper analysis\" or \"needs broader architectural changes\" is narrating — not doing. If the goal is not met, your job is to keep working, not to write a summary of why the remaining work is hard.

HONESTY CHECK: Before marking anything as \"not possible\" or \"skipped\", ask yourself: did you actually TRY, or are you rationalizing skipping it because it seems hard or inconvenient? \"I can't do X\" is almost never true — what you mean is \"I haven't tried X yet.\" If you haven't attempted something, you don't get to claim it's impossible. Attempt it first.

When and only when everything is genuinely 100% done (or explicitly deprioritized by the user), include this exact line in your final response on its own line:
${DONE_SIGNAL}

Do NOT emit that done signal early. If any work remains, continue working now."

jq -n --arg reason "$REASON" '{ decision: "block", reason: $reason }'
