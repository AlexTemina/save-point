# Save Point

A macOS app for the day's plan, with a menu bar item that is always there. Named after the people of Outer Wilds, who travel with a campfire and a rocket. It shows a ranked queue of what to do today, keeps it live as the plan file changes, and jumps to the [Orca](https://onorca.dev) agent working on each item.

Save Point does not plan anything itself. Something else writes `~/Library/Application Support/Save Point/today.json` (in the author's setup, a Claude Code workflow over a notes vault), and Save Point reads it every two seconds.

## What it does

- **Menu bar:** `☀️ 4/15`, done over total in today's queue. Click for the day: the focus (the one thing that makes the day), the fixed slots, the queue with the next item marked, what runs in parallel.
- **Window:** a sidebar with the day, what runs in parallel, decisions, what is out today and every section of the map, each with its count. Closing it keeps Save Point in the menu bar; the Dock icon brings it back.
- **Open at login:** a switch in Settings.
- **On each item:** click opens its first link. Three buttons on hover:
  - Robot: go to its agent in Orca. The live agent of the item's worktree, or a new one there, or a new one in the fallback worktree.
  - bb: the robot's path in [bb](https://github.com/get-bb/bb). Only Claude threads: the one that names the item's issue, or the one in its worktree, or a new one there, or a new one in the fallback worktree.
  - Robot with a speech bubble: write a message right there, ⌘↩ sends it to that live agent.
  - Robot with a plus: start a fresh agent, with the start prompt ready to edit.
- **Right click:** the same, plus open any of its links and copy the line.
- **Languages:** English and Spanish, picked in Settings (or follow the system).

An item finds its worktree by the Linear issue Orca has linked to it, or by a PR number.

## today.json

```json
{
  "date": "2026-10-19", "eyebrow": "Lunes 19 de octubre de 2026", "week": "…",
  "focus": Item, "slots": [{"time": "11:00", "title": "La Una", "text": "…"}],
  "queue": [Item], "parallel": [Item], "decisions": [Item],
  "while_waiting": "…", "not_today": "…",
  "sections": [{"title": "🔴 Needs attention", "items": [Item]}],
  "progress": {"done": 3, "total": 15}
}
```

`Item`: `{"text", "md", "status": "open|done|moved|snoozed|skipped|dropped|waiting", "size", "tags": [], "links": [{"title", "url"}], "issue", "pr"}`.

## Config

`~/Library/Application Support/Save Point/config.json`, all optional:

```json
{
  "fallbackWorktree": "/path/to/an/orca/worktree",
  "startPrompt": "Start working on {target}: {text}",
  "resumePrompt": "Continue with {target}: {text}",
  "permissionMode": "auto"
}
```

## Build

macOS 14+, Xcode command line tools, Orca in `/Applications`, `claude` on the login shell `PATH`.

```sh
./scripts/bundle.sh     # build, install in /Applications, launch
./scripts/package.sh    # dist/Save Point-<version>.dmg, drag to Applications
```

Signing uses a code-signing identity named `Save Point Local Signing` if your keychain has one (set `SAVEPOINT_SIGN_IDENTITY` for another), so macOS keeps its permissions across rebuilds; otherwise it signs ad-hoc. Save Point runs the Orca CLI, which lives inside `Orca.app`, so macOS asks once for App Management.

## License

MIT
