# seshka

**Kill what Claude Code left behind.**

Claude Code sessions end. The dev servers, watchers and emulators they started don't.
seshka is a macOS menu bar app that finds them and kills them.

![seshka listing 11 leftover processes from 4 closed sessions, and the same popover after killing them: Freed 2.2 GB](docs/screenshot.png)

## What it does

- Finds every process started by a Claude Code session that has since closed.
- Groups them by session, with their ports, memory and age.
- Kills one process, one session's worth, or all of them.
- Tells you how much memory they were holding.
- Shows every open session too: whether it is working or idle, for how long, and what it holds.
- Ends idle sessions in one click, or on its own once they have waited longer than you allow (two hours unless you change it; off until you turn it on).

The doll in the menu bar is open while something is left behind, and closed when your Mac is clean.

## Install

**[Download for macOS](https://seshka.dev/download/Seshka.dmg)**, open the disk image and drag Seshka to Applications.

Requires macOS 14 or later, on Apple silicon or Intel. The app is signed and notarized, and keeps itself up to date.

To build it yourself:

    scripts/build.sh
    open build/Seshka.app

## How it works

Claude Code sets `CLAUDECODE=1` in the environment of everything it starts, along with the ID of the session
and of its own process. seshka reads those from your running processes. A process is a leftover once the
Claude Code process that started it is gone.

Nothing leaves your Mac.

## License

MIT. Copyright (c) 2026 JigJoy. See [LICENSE](LICENSE).

---

Built by the [JigJoy](https://jigjoy.ai) team · Issues: [github.com/jigjoy-ai/seshka/issues](https://github.com/jigjoy-ai/seshka/issues) · Twitter: [@lotus_sbc](https://twitter.com/lotus_sbc)
