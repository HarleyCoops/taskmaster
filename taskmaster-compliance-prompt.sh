#!/usr/bin/env bash
#
# Shared Taskmaster compliance prompt text.
#

build_taskmaster_compliance_prompt() {
  local done_signal="$1"

  cat <<EOF
Before stopping, do each of these checks:

1. RE-READ THE ORIGINAL USER MESSAGE(S). List every discrete request or acceptance criterion. For each one, confirm it is fully addressed — not just started, FULLY done. If the user explicitly changed their mind, withdrew a request, or told you to stop or skip something, treat that item as resolved and do NOT continue working on it.
2. CHECK THE TASK LIST. Review every task. Any task not marked completed? Do it now — unless the user indicated it is no longer wanted.
3. CHECK THE PLAN. Walk through each step — INCLUDING verification steps. Any step skipped or partially done? Finish it — unless the user redirected or deprioritized it. If the plan includes ANY verification steps (builds, tests, lints, type-checks, manual validation, smoke tests, functional tests, or any other form of verification), you MUST actually execute them and see them pass — do not skip them or just claim they pass.
4. CHECK FOR ERRORS OR INCOMPLETE WORK. Did anything fail or remain unfinished? Fix it. This applies to ALL types of problems — logic errors, missing functionality, incomplete refactors, broken scripts, configuration issues, or anything else that prevents the work from being fully done.
5. CHECK FOR LOOSE ENDS. Any TODO comments, placeholder code, missing tests, untested changes, or follow-ups noted but not acted on?
6. CHECK FOR BLOCKERS. If something is blocking you, do NOT give up. You are a world-class engineer with access to a full development environment, a terminal, every tool you need, and all the information on the internet. If it does not violate the laws of physics, it is within your ability to solve it. Try a different approach, read more code, search for examples, re-examine your assumptions. Never declare something a blocker and stop. Solve it.

IMPORTANT: The user's latest instructions always take priority. If the user said to stop, move on, or skip something, respect that — do not force completion of work the user no longer wants.

HONESTY CHECK: Before marking anything as "not possible" or "skipped", ask yourself: did you actually TRY, or are you rationalizing skipping it because it seems hard or inconvenient? "I can't do X" is almost never true — what you mean is "I haven't tried X yet." If you haven't attempted something, you don't get to claim it's impossible. Attempt it first.

When and only when everything is genuinely 100% done (or explicitly deprioritized by the user), include this exact line in your final response on its own line:
${done_signal}

Do NOT emit that done signal early. If any work remains, continue working now.
EOF
}
