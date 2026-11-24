---
description: Kill what closed Claude Code sessions left running on this Mac, through the seshka app. Only when the user asks for it.
argument-hint: "[here]"
disable-model-invocation: true
allowed-tools: Bash(seshka --leftovers:*) Bash(seshka --clean:*)
---

Kill the processes that closed Claude Code sessions left running. Open sessions and what they run are never touched, and neither are the processes the user has marked as protected in seshka.

1. Run `seshka --leftovers`, or `seshka --leftovers --here` from the project's folder if the user wrote `here` or asked only about this project. Show the user the list.
2. If nothing is left, say so and stop.
3. Run `seshka --clean`, with the same `--here` if you used it in step 1.
4. Report what it printed: how many were killed, how much memory came back, and anything that was left alone or is still running.

$ARGUMENTS
