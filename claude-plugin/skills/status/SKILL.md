---
description: Show what closed Claude Code sessions left running on this Mac, as the seshka app sees it (dev servers, watchers, databases, with their ports and memory). Use when a port is already in use, when the machine is short of memory, or when the user asks what is still running.
argument-hint: "[here]"
allowed-tools: Bash(seshka --leftovers:*)
---

Show the user what closed Claude Code sessions left running.

Run `seshka --leftovers`. If the user wrote `here`, or asked only about this project, run `seshka --leftovers --here` from the project's folder instead. The `seshka` command comes with this plugin and runs the seshka app's own command line.

Then report what it printed, shortly: how many processes, how much memory in all, and for each one its command, port and age. Do not kill anything. If the user wants them gone, `/seshka:clean` does it.

If the command says seshka is not installed, tell the user so and give them the address it prints.

$ARGUMENTS
