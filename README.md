# PromptBoard

A macOS prompt **and skill** manager that lives in your menu bar. Press **⌥Space** anywhere and a full-screen overlay appears over a blurred desktop, showing your prompts and skills as a Pinterest-style masonry grid.

- **Single-click** a card → copies the prompt to the clipboard (overlay stays open)
- **Double-click** a card → edit it
- **Two-finger scroll** → browse the grid
- **Type** → live-search prompts (search is focused on open)
- **⌘N / +** → new prompt · hover **✕** → delete
- **Esc** → clears search, then closes · **⌥Space** or click empty space → closes

## Library layout

Everything lives as human-readable files under `~/Library/Application Support/PromptBoard/Library/`:

```
Library/
├── prompts/<slug>.md      # frontmatter (id, title, group, dates) + markdown body
└── skills/<name>/         # an Agent Skill: spec-pure SKILL.md + supporting files
    ├── SKILL.md           #   name + description + body (PromptBoard adds nothing here)
    └── .promptboard.json  #   sidecar: id, group, timestamps
```

- **Files are the source of truth** — no central index. Add, edit, or drop in items by hand and the app live-reloads them.
- Each skill is **symlinked into `~/.claude/skills/<name>`** so Claude Code can use it directly; PromptBoard never overwrites a path it didn't create.
- A legacy `prompts.json` is **migrated once** on first launch or first CLI/MCP access, then kept as a `prompts.json.migrated-<stamp>` backup (never deleted).

## Build & run

```bash
swift build          # compile
swift test           # unit tests (repository, store, filter, masonry)
swift run PromptBoardApp   # dev loop (menu bar icon appears; Ctrl-C to quit)
make app             # assemble + ad-hoc sign dist/PromptBoard.app
open dist/PromptBoard.app
make install         # build + install the promptboard CLI to ~/.local/bin
```

Requires macOS 14+. No Xcode project — pure SwiftPM. For **Launch at Login**, run the bundled `dist/PromptBoard.app` (the toggle is disabled under `swift run`; move the app to `/Applications` for a stable login item).

⚠️ Don't run `swift run PromptBoardApp` and the bundled app at once — the second instance's hotkey registration fails (logged to console).

## Agent access (CLI + MCP)

The `promptboard` binary gives scripts and AI agents full CRUD over the same library, and the app live-reloads external changes — no relaunch. Conflicts are last-writer-wins per save; an editor open in the overlay keeps its draft until saved.

```
promptboard list   [--query <q>] [--type prompt|skill] [--group <g>] [--json]
promptboard get    <id> [--json]              # prompt text, or a skill's SKILL.md, on stdout
promptboard get    <id> --list-files          # a skill's supporting files, one per line
promptboard get    <id> --file <relpath>      # one of a skill's files, on stdout
promptboard add    [--title <t>] (--content <text> | --content-file <path|->) [--group <g>]
promptboard update <id> [--title <t>] [--content <text> | --content-file <path|->] [--group <g>]
promptboard delete <id> [--json]              # a prompt or a skill
promptboard import-skill <dir> [--group <g>]  # copy an Agent Skill folder in + link it
promptboard relink                            # re-establish ~/.claude/skills symlinks (no-clobber)
promptboard mcp                               # stdio MCP server (tools only)
```

- Every subcommand accepts `--data-dir <path>` (or `$PROMPTBOARD_DATA_DIR`); ids are UUIDs from `list` (its second column is `prompt` or `skill`).
- `--content-file -` reads stdin. `update` preserves omitted fields.
- `--json` prints flat, `kind`-tagged objects with the same ISO-8601 fractional dates as on disk. Timestamps are output-only — the store manages them.
- Exit codes: 0 ok · 1 I/O or lock timeout · 2 not found · 64 usage.
- The CLI never seeds samples: `list` on an empty library prints nothing and creates nothing. A single malformed file is skipped (logged to stderr), never fatal. A legacy `prompts.json` is migrated on first access.

MCP tools (7): `list_prompts` (`query?`), `get_prompt` (`id`), `add_prompt` (`title?`, `content`, `group?`), `update_prompt` (`id`, `title?`/`content?`/`group?`), `delete_prompt` (`id`), `list_skills` (`query?`), `get_skill` (`id` → SKILL.md body + file list). Registration:

```bash
claude mcp add --scope user promptboard -- ~/.local/bin/promptboard mcp   # Claude Code
```

```toml
# Codex: ~/.codex/config.toml (absolute path — no ~ expansion)
[mcp_servers.promptboard]
command = "/Users/arya/.local/bin/promptboard"
args = ["mcp"]
```

### Dev hooks (env vars)

- `PROMPTBOARD_SHOW_ON_LAUNCH=1` — open the overlay immediately at launch
- `PROMPTBOARD_DATA_DIR=/path` — use a different library directory (keeps your real library untouched)
- `PROMPTBOARD_CLAUDE_SKILLS_DIR=/path` — where the CLI/MCP symlink skills (default `~/.claude/skills`); handy for isolated tests
- `PROMPTBOARD_DEBUG=1` — listen for distributed notifications used for scripted UI verification: `com.arya.PromptBoard.debug.toggle` (toggle overlay), `…debug.newPrompt` (open overlay + blank editor), `…debug.commandKey` (replay a ⌘-key equivalent; object = character, e.g. `"v"`), `…debug.dumpState` (log key window, first responder, and each text field's value/focus), `…debug.dumpPrompts` (log item count + titles), `…debug.snapshot` (write a PNG of the overlay content; object = output path). Post one with:

  ```bash
  swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.dumpState"), object: nil, userInfo: nil, deliverImmediately: true); Thread.sleep(forTimeInterval: 0.3)'
  ```

## Smoke checklist

1. Launch → menu-bar grid icon appears, no Dock icon.
2. From another app, press ⌥Space → full-screen overlay, desktop visibly **blurred** (not just dimmed), no app switch.
3. Search field is focused immediately; typing filters cards live (title + body, case-insensitive). ⌘V pastes into the search field.
4. Esc with text in search → clears it; Esc again → closes. ⌥Space toggles closed. Click empty background → closes.
5. After closing, keystrokes land in the previously active app with no extra click.
6. ⌥Space over a full-screen app's Space → overlay appears there.
7. Single-click a card → "Copied ✓" badge ~1s, `pbpaste` matches, overlay stays open.
8. Double-click a card → editor opens pre-filled with the title field focused; ⌘S saves; Esc closes the editor only and focus returns to search. ⌘V/⌘C/⌘X/⌘A and undo work in both editor fields.
9. + button or ⌘N → blank editor; save → card appears in the grid.
10. Hover a card → ✕ appears; click deletes. Delete also available inside the editor.
11. Two-finger scroll through a long grid; columns stay balanced as cards change.
12. Quit + relaunch → data persists. A malformed `.md` in `Library/prompts` is skipped (logged), the rest still load. A legacy `prompts.json` migrates into `Library/` on launch and is kept as a `.migrated-*` backup.
13. Bundled app only: Launch at Login toggle flips the checkmark and appears in System Settings → General → Login Items.
14. `promptboard add --title X --content Y` while the overlay is open → card appears within ~1s, no relaunch; an edit saved in the app shows up in `promptboard list` immediately.
15. `promptboard import-skill <dir>` → a skill card appears within ~1s and a symlink lands in `~/.claude/skills/<name>` (unless a real folder of that name is already there, which is left untouched).
