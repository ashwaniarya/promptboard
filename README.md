# PromptBoard

A macOS prompt **and skill** manager that lives in your menu bar. Press **⌥Space** anywhere and a full-screen overlay appears over a blurred desktop, showing your prompts and skills as **markdown-rendered cards**.

- **Single-click** a card → copies the raw markdown to the clipboard (overlay stays open)
- **Double-click** a prompt → edit it · a skill → expand (file tree beside its rendered `SKILL.md`), then **Edit** to open the skill editor
- **Groups sidebar** filters the grid; the **column toggle** (2 / 3 / 4) sets density
- **Type** → live-search across titles and bodies (focused on open)
- **+** → new prompt (**⌘N**) or **new skill** · hover a skill **✎** → edit · hover a prompt **✦** → convert it into a skill · hover **✕** → delete
- **Esc** → closes the editor/detail, then clears search, then closes · **⌥Space** or empty-space click → closes

## Quick-insert at the cursor

Press **⌥/** (option-slash) in any app to drop a compact search popup at your text caret. Type to filter your prompts — the slug doubles as a `/command` (e.g. `/code-review`) — then **↑↓** to choose and **⏎** to insert the prompt's text right where you were typing. **Esc** dismisses.

- **Insert-at-caret needs Accessibility permission** (System Settings → Privacy & Security → **Accessibility** → enable PromptBoard). A fresh grant may need one relaunch. Until granted, the popup still works but **copies** the prompt to the clipboard (paste with ⌘V) and asks for access.
- The popup lists **prompts only** — skills stay agent-invoked (via the `~/.claude/skills` symlink / MCP).
- Insertion pastes via the clipboard and restores it afterward (text only). Positioning uses the Accessibility caret rect, falling back to the mouse when an app doesn't expose it.

## Cross-tool sync

PromptBoard syncs your prompts and skills to every agent CLI on the machine — **Claude Code, Codex, Cursor, and OpenCode** — so a prompt you save here becomes a `/slash-command` everywhere.

- **Two directories reach all four tools.** Skills are symlinked into **`~/.agents/skills`** (read by Codex, Cursor, OpenCode) and **`~/.claude/skills`** (read by Claude Code). Their union is complete coverage — no per-tool fan-out.
- **Prompts sync as skills.** Each prompt is rendered into a minimal Agent Skill under `~/Library/Application Support/PromptBoard/Export/skills/<slug>/` (a `SKILL.md` marked `disable-model-invocation: true`, plus `agents/openai.yaml` for Codex), then symlinked into both dirs. So `/code-review` shows up as a user-invoked command in each tool. Editing the prompt regenerates it; deleting it removes the links.
- **Nothing is copied — everything is a symlink** back into your library, so edits propagate instantly with no sync step and no drift. Ownership is derived from where a link resolves (no manifest file); a path PromptBoard didn't create is never touched, and a name clash surfaces as a **conflict badge** rather than an overwrite.
- **Adopt what already lives in your tools.** Skills sitting in any tool's own directory show on the board as read-only cards **badged by origin**. **Adopt** one to pull it into your library: **Copy** leaves the original untouched, **Move** backs it up (a hidden `.<name>.promptboard-backup-*`) and replaces it with a link so it then syncs everywhere. Toggle **Show external** in the sidebar to hide them.
- **Left alone:** Codex's `~/.codex/skills/.system` cache and Cursor's tool-managed `~/.cursor/skills-cursor`.

> Claude Code is confirmed to load symlinked skills (this is how it already picks up `~/.claude/skills` links). Cursor and OpenCode read the same directories via standard globbing, which is symlink-transparent; if a future tool version filters symlinks, the sync layer can mirror real copies into that one tool's dir.

## Folders

Organize prompts and skills into **nested folders** — real directories, not tags. The sidebar is a tree you can expand and collapse; selecting a folder shows its items **and everything in its subfolders** (Finder-style).

- **A folder is a directory.** An item's folder is wherever its file/folder lives under `prompts/` or `skills/` — there's no stored `group` field anymore; the folder is derived from location. Root-level items stay at the top, ungrouped.
- **Move by dragging** a card onto a folder row (or onto **All** to un-folder it). Create a folder with the **+** in the sidebar's GROUPS header; a freshly created empty folder shows right away.
- **Deleting a folder never deletes its contents** — the items move up to the parent. Renaming a folder moves everything inside it with it.
- **`group` means "folder" everywhere it's set.** In the CLI/MCP, `add --group Work/ClientA` files a prompt into `prompts/Work/ClientA/`, and `update --group`, `import-skill --group`, and `update-skill-group` move the item into that folder. In the editor/convert sheets, the "group" field does the same.
- **Cross-tool sync is unaffected.** Skills sync by their flat leaf name regardless of how deep they're nested — a skill in `skills/Work/logo-export/` still shows up as `/logo-export` in every tool. Your old flat groups migrate to top-level folders once, automatically, on first launch.

## Library layout

Everything lives as human-readable files under `~/Library/Application Support/PromptBoard/Library/`:

```
Library/
├── prompts/
│   ├── <slug>.md              # frontmatter (id, title, dates) + markdown body
│   └── Work/ClientA/<slug>.md #   nested = filed under the "Work/ClientA" folder
└── skills/
    ├── <name>/                # an Agent Skill: spec-pure SKILL.md + supporting files
    │   ├── SKILL.md           #   name + description + body (PromptBoard adds nothing here)
    │   └── .promptboard.json  #   sidecar: id, timestamps
    └── Brand/<name>/          #   nested = filed under the "Brand" folder
```

- **The folder is the truth** — an item's `group` is derived from where its file lives, not stored in frontmatter or the sidecar. Move the file (by hand or by drag) and its folder changes.
- **Files are the source of truth** — no central index. Add, edit, or drop in items by hand and the app live-reloads them.
- Each skill is **symlinked into `~/.claude/skills/<name>`** so Claude Code can use it directly; PromptBoard never overwrites a path it didn't create.
- **Skills are authored in-app** — the skill editor edits `SKILL.md` (name / description / body) and manages supporting files (create, rename, delete, import from disk); renaming a skill renames its folder and re-points the symlink, skipping (with a warning) any foreign `~/.claude/skills` name. Metadata and file text commit on **Save**; file add/rename/delete apply immediately.
- A legacy `prompts.json` is **migrated once** on first launch or first CLI/MCP access, then kept as a `prompts.json.migrated-<stamp>` backup (never deleted).

## Build & run

```bash
swift build          # compile
swift test           # unit tests (repository, store, filter, skill authoring, promote)
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
- `PROMPTBOARD_CLAUDE_SKILLS_DIR=/path` — one of the two sync target dirs (default `~/.claude/skills`); handy for isolated tests
- `PROMPTBOARD_AGENTS_SKILLS_DIR=/path` — the other sync target dir (default `~/.agents/skills`). Both must be absolute (a `~` is expanded; a relative value is ignored with a warning, so a stray value never scatters links)
- `PROMPTBOARD_EXTERNAL_SCAN_ROOTS=/a:/b` — colon-separated absolute paths to scan for adoptable external items, **replacing** the built-in per-tool table (everything found is badged `External`); essential for isolating the adopt flow in tests away from your real tool dirs
- `PROMPTBOARD_DEBUG=1` — listen for distributed notifications used for scripted UI verification: `com.arya.PromptBoard.debug.toggle` (toggle overlay), `…debug.newPrompt` (open overlay + blank editor), `…debug.commandKey` (replay a ⌘-key equivalent; object = character, e.g. `"v"`), `…debug.dumpState` (log key window, first responder, and each text field's value/focus), `…debug.dumpPrompts` (log item count + titles), `…debug.snapshot` (write a PNG of the overlay content; object = output path). Skill-editor hooks: `…debug.createSampleSkill` (object = name), `…debug.editFirstSkill`, `…debug.newSkill`, `…debug.convertFirstPrompt`, `…debug.confirmConvertFirst`, `…debug.addSampleFiles`. Cross-tool-sync hooks: `…debug.dumpExternal` (log discovered external items + origins), `…debug.adoptFirstExternal` (object = `"move"` / `"copy"`), `…debug.beginAdoptFirst` (open the adopt sheet without committing), `…debug.dumpSyncConflicts`. Post one with:

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
16. Cards render markdown (headings, lists, **bold**, `code`, code blocks); single-click still copies the **raw** markdown.
17. The column toggle (2 / 3 / 4) reflows the grid; the groups sidebar filters and shows live counts.
18. Hover a card → **⤢** expands it: a prompt shows full markdown; a skill shows its file tree beside `SKILL.md` (select a file to view it). Esc or an outside click closes it.
19. `+` → **New skill** → an empty editor; type a name + one-line description → **Create** → a skill card appears, `SKILL.md` holds only `name` + `description`, and a symlink lands in `~/.claude/skills/<name>` (`claude` lists it).
20. A skill's detail → **Edit** (or hover a skill **✎**) → the editor loads name/description/group + the file rail. Change the body, **Save** → the card and `SKILL.md` update; the sidecar keeps the id.
21. In the skill editor: **New** → `examples/ref.md` appears nested and editable; rename and delete it; **Import** pulls a file from disk; a non-text file shows "Binary file — rename or delete only". Rename the skill → its folder and `~/.claude/skills` symlink follow the new name (a foreign name is skipped with a warning).
22. Hover a prompt **✦** → **Convert to skill** → name prefilled; add a description → **Convert** → a skill opens in the editor with the prompt's content as its `SKILL.md` body, and the original prompt is gone (unless "keep the original prompt" is checked).
23. Grant Accessibility to PromptBoard, then in TextEdit press **⌥/** → a compact popup appears at the caret; type `/code-review` (or `review`) → the list ranks/filters; **⏎** inserts the prompt's text at the cursor and the clipboard is restored. ⌥Space board still works independently.
24. Before granting Accessibility, ⌥/ → picking a prompt **copies** it and raises the permission prompt instead of inserting.
25. Add a prompt → within ~1s a `<slug>` skill link appears in **both** `~/.agents/skills` and `~/.claude/skills` (and `Export/skills/<slug>/SKILL.md` is generated); `claude` offers it as `/<slug>`. Delete the prompt → both links and the export vanish. A foreign folder already at that name is left untouched and the card shows a conflict badge.
26. A skill living only in another tool (e.g. `~/.codex/skills/<x>`) shows as a dimmed **external** card badged by origin. **Adopt → Copy** leaves the original byte-identical and adds it to the library (now synced to all tools); **Adopt → Move** replaces the original with a link and leaves a hidden `.<x>.promptboard-backup-*`. **Show external** in the sidebar hides these.
27. `find ~/.agents/skills ~/.claude/skills -type l ! -exec test -e {} \;` prints nothing — no dangling links left by any add/edit/delete/rename/adopt.
