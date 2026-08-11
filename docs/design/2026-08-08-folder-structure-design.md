# Design — Nested Folders (Layer F)

Status: implemented 2026-08-11 · Scope: Layer F (organization) · Plan: docs/plans/2026-08-08-folder-structure.md

## Why

Prompts and skills currently carry one flat, optional `group: String?` label (`Prompt.swift`,
`Skill.swift`, surfaced through `LibraryEntry.group`) — no nesting, no multi-membership, and
`AppState.selectedGroup` filters by exact string match. Arya wants real folder structure to
organize a growing library — user-created, nested folders, not a flat tag list. This is Layer F.

## Locked decisions

1. **Folders are real nested directories.** A folder path is the item's containing directory path
   under `Library/prompts/` or `Library/skills/`. This **replaces** `group: String?` outright — no
   parallel field, no dual bookkeeping.
2. **Migration is a directory move, not a format rewrite.** Each distinct existing `group` becomes
   a top-level folder; every item with that group moves into it. Items with no group stay at the
   library root. No backup copy — nothing is lost or reformatted, only relocated (unlike the
   `prompts.json` migration, which changed shape and does keep a dated backup).
3. **Sidebar becomes a real tree.** Expand/collapse chevrons, indentation per depth. Selecting a
   folder shows its items **and** everything in its subfolders (Finder's "enclosing folder"
   behavior), not drill-only.
4. **Move is drag-and-drop only for v1.** No folder picker in the create/edit sheets. Dropping a
   card on the sidebar's **All** row moves it to the library root (un-foldering it) — the only other
   way to change an item's folder in v1.
5. **Deleting a non-empty folder moves its contents up** to the parent (or root, for a top-level
   folder) rather than cascading a delete or blocking outright — matches this app's existing
   never-destroy-by-default posture (skill rename, `prompts.json` migration, adopt-move backups).
6. **Slugs are unique within a folder, not globally.** Layer E's existing `SyncConflict` badge is
   already the backstop for a same-named collision once two folders' items flatten into sync.
7. **Cross-tool sync is untouched.** It is already flat and keyed by slug/name — folder nesting is
   invisible to it by construction.

## Scope calls

- No folder picker in the editor sheets (decision 4) — drag-and-drop only.
- No multi-select / bulk move in v1 — one item dragged at a time. YAGNI until asked for.
- No folder icons, colors, or metadata — a folder is a name and a path, matching the minimalism of
  everything else in the library (no central index, files are the source of truth).
- CLI/MCP folder operations are deferred, the same call Layer C made for skill authoring — the Kit
  primitives are built reusable so exposing them later is cheap.

## New Kit primitives (`LibraryRepository`)

- `createFolder(kind:path:) throws` — `kind` is `.prompt` or `.skill` (separate trees); creates the
  directory (and intermediate parents); rejects a path that already exists or escapes the library
  root.
- `renameFolder(kind:from:to:) throws` — renames the directory in place; every descendant moves for
  free (one `FileManager.moveItem`). For the skills tree, every descendant skill's sync symlink is
  repointed afterward, reusing the repoint call Layer C's skill-rename mechanic already makes,
  looped over each skill under the moved subtree.
- `deleteFolder(kind:path:) throws` — moves direct children (files and subfolders) up to the
  parent, then removes the now-empty directory.
- `movePrompt(id:toFolder:) throws` / `moveSkill(id:toFolder:) throws` — relocates the single
  file/directory; a skill move repoints its symlink the same way rename does.
- `load()` becomes a recursive walk (was one-level `contentsOfDirectory`) — the one existing method
  whose behavior changes rather than a pure addition.

## Store surface (`LibraryStore`)

Non-throwing wrappers over each primitive, same pattern as Layer C: call through,
`refreshFromDisk()`, return success/failure logged to stderr on failure.

## App wiring

- `AppState`: `selectedGroup: String?` → `selectedFolder: String?` holding a full relative path;
  the exact-match filter becomes a prefix match (own folder or `hasPrefix(selectedFolder + "/")`);
  `groupCounts` becomes a tree-shaped `folderTree` computed property.
- `GroupSidebarView` → recursive tree rendering (a folder row renders its own children), chevron
  expand/collapse state, a **+** affordance for new-folder creation scoped to the currently
  selected folder.
- `LibraryGridView` / `PromptCardView`: cards gain drag support (`.draggable`/`NSItemProvider`
  carrying the item's id); sidebar folder rows (and the **All** row) gain a drop destination that
  calls `movePrompt`/`moveSkill`.
- `DebugHooks`: notifications to script folder create/rename/delete/move and expand/collapse, for
  harness verification (same pattern as every prior layer).

## Testing

- 🔬 **Kit unit:** recursive scan discovers nested items at every depth; create/rename/delete/move
  each round-trip on disk; rename moves every descendant and repoints every descendant skill's
  symlink; delete-non-empty relocates children instead of losing them; migration converts each
  distinct group to a folder and leaves no-group items at the root; slug uniqueness is enforced
  per-folder, not globally.
- 🎭 **Store/App behavioural (harness):** sidebar tree renders correct nesting + counts; selecting a
  folder includes subfolder items; drag-move relocates a card and its file moves on disk; a moved
  skill's `~/.claude/skills` symlink still resolves; dropping on **All** clears an item's folder.
- 💨 **Smoke:** real app — create a folder, drag a prompt into it, confirm the file moved in Finder
  and the prompt still opens; drag a skill into a folder, confirm the CLI/Claude Code still finds
  it.

## Phases

- **F0** — Kit: recursive scan + folder CRUD primitives + unit tests
- **F1** — Kit: move primitives (prompt/skill) + symlink repoint on folder rename + tests
- **F2** — Kit: migration (flat group → folder) + tests
- **F3** — Store wrappers + `AppState` (`selectedFolder`, `folderTree`) + tests
- **F4** — Sidebar tree UI (expand/collapse, create-folder affordance)
- **F5** — Drag-and-drop move (cards → sidebar folders, including the **All** root-drop)
- **F6** — Smoke, docs, memory
