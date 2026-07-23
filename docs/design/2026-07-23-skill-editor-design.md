# Design — In-App Skill + File Editor

Status: approved 2026-07-23 · Scope: Layer C (authoring)

## Why

Layers A and B made skills first-class in the library and on the board, but they are still
**read-only** inside the app: PromptBoard can import, view, symlink, and delete a skill, but it
cannot author one. The only editor is `PromptEditorView` (title + content, prompts only). Layer C
closes that gap — creating and editing skills, their `SKILL.md`, and their supporting files from
inside the ⌥Space overlay — and adds the bridge the user asked for: turning a large prompt into a
skill.

This is the third of four layers (A — library core ✅, B — redesigned board ✅, **C — skill + file
editor**, D — cursor quick-insert). Layer D is out of scope here.

## Locked decisions

1. **Editor layout: editable detail (Option A).** The existing read-only detail overlay gains an
   Edit mode with the same two-pane shape (file rail + content pane) rather than a separate
   IDE-style window. Least new surface, most cohesive with what is built.
2. **Skill rename: rename + re-link.** Changing a skill's `name` renames its library folder and
   re-points its `~/.claude/skills` symlink so folder == name stays true; the sidecar `id` is
   untouched, and a foreign collision at the new symlink path is skipped + warned (no clobber).
3. **File ops: full.** Edit text files in-app, create new files (including into subfolders),
   rename, delete, and import an existing file from disk.
4. **Prompt → skill: included.** A Convert action promotes a prompt's content into a new skill's
   `SKILL.md` body and removes the original prompt (a "keep original" toggle defaults off).

## Scope calls

- **CLI/MCP skill-authoring tools are deferred.** Layer C is the in-app editor. The new repository
  primitives are built reusable so a later pass can expose `create_skill` / `update_skill` /
  `write_skill_file` to Claude Code cheaply. Read-side `list_skills` / `get_skill` already exist.
- **Deep external file-watching is deferred.** Our own edits refresh the store immediately. An
  external edit *inside* a skill folder (e.g. `vim reference.md`) is picked up on the next coarse
  reload of the `skills/` directory, not live. YAGNI until asked for.

## New Kit primitives (`LibraryRepository`)

All are self-locking (`withExclusiveLock`), non-reentrant, atomic per-file writes, and honor the
symlink no-clobber rule. They live in a new `LibraryRepository+SkillAuthoring.swift` extension so the
core file stays manageable.

- `createSkill(name:description:group:body:) -> Skill` — folder `skills/<slug(name)>/` (unique,
  case-insensitive de-dup), spec-pure `SKILL.md` (`name` + `description` + body), sidecar with a new
  `id` + timestamps, then symlink (warn on foreign conflict).
- `updateSkill(id:name:description:group:body:) -> Skill` — full-state save: rewrite `SKILL.md`
  (name/description/body) and the sidecar (`group`, `updatedAt`). When the name changes, run the
  rename mechanic below.
- `writeSkillFile(id:relativePath:data:) -> Skill` — create/overwrite a supporting file; creates
  intermediate directories for nested paths (`examples/card.json`); refuses `SKILL.md` and
  `.promptboard.json`; refuses paths escaping the folder (same guard as `skillFileData`).
- `renameSkillFile(id:from:to:) -> Skill` — move within the folder; same guards; missing source
  errors; refuses reserved targets.
- `deleteSkillFile(id:relativePath:) -> Skill` — remove one supporting file; same guards.
- `promotePromptToSkill(promptID:name:description:group:removingPrompt:) -> Skill` — create a skill
  whose body is the prompt's content, then (if `removingPrompt`) delete the prompt file. Both under
  one lock; skill-first so a mid-flow failure never loses the prompt.

Import-from-disk needs no primitive: the app reads the chosen file's bytes and calls
`writeSkillFile`. Group editing folds into `updateSkill` (the editor always saves full state), so
the existing `updateSkillGroup` stays only for the CLI.

## The rename mechanic

Inside `updateSkill`, when the new name's slug differs from the current folder name:

1. Compute `newFolderName = Slug.unique(Slug.make(from: newName), existing: our other skill folders)`.
2. `SymlinkManager.unlink(oldFolderName, expectedTarget: oldFolder)` — removes the link only if it is ours.
3. Move the library folder `oldFolder → newFolder` (our namespace; can't collide with foreign paths).
4. `SymlinkManager.link(newFolder, name: newFolderName)` — no-clobber; if `~/.claude/skills/<newFolderName>`
   is foreign, skip + warn (the library folder is still renamed).
5. Write `SKILL.md` + sidecar into the new folder.

The sidecar `id` is preserved, so PromptBoard identity and the live-reload content signature survive
the rename with no duplicate card.

## Store surface (`LibraryStore`)

Non-throwing wrappers, each calling the primitive then `refreshFromDisk()` (which recomputes the
content signature so the follow-on watcher event is suppressed as a self-write):

`createSkill`, `updateSkill`, `writeSkillFile`, `renameSkillFile`, `deleteSkillFile`,
`promotePromptToSkill` — all returning the resulting `Skill?` (nil on repository failure, logged to
stderr, matching the existing pattern).

## Editor UX (Option A)

- **Enter edit:** a skill card's double-click opens the read detail as today; an **Edit** toggle (and
  a hover ✎ on the card) enters edit mode — header `name` / `description` / `group` become fields, the
  file rail gains `+ new` / import / per-row rename + delete, and the content pane becomes a
  `TextEditor` for the selected file. `SKILL.md` is pinned and selected by default. Non-text files
  (undecodable as UTF-8) show a "rename or delete only" placeholder instead of a text editor.
- **New skill:** the `+` control becomes a menu (*New prompt* / *New skill*). Create mode opens the
  editor empty; the **first Save** calls `createSkill` and materializes the folder, after which file
  management unlocks (a hint explains this before the first save).
- **Save model — content transactional, structural immediate:**
  - `name` / `description` / `group` and each file's **text** buffer in memory (a
    `[relativePath: String]` dirty map, so several files can be edited then saved once); **Save**
    writes them all; **Cancel** discards them.
  - **new / rename / delete / import apply immediately** (like an IDE sidebar), so Cancel does not
    undo those structural operations. Chosen over a fully-transactional virtual tree (much more
    state) and a no-Save live model (no discard).

## Convert prompt → skill

A hover ✦ action on a prompt card opens a small sheet: `name` (prefilled from the title),
`description` (required), `group` (carried over), and a "keep original prompt" toggle (default off).
Confirm calls `promotePromptToSkill` (body = the prompt's content) and opens the new skill in the
editor. The folder already exists, so file ops work immediately.

## App wiring

- `AppState`: add `enum SkillEditorMode { case create; case edit(Skill) }` + `skillEditorMode:
  SkillEditorMode?`, with `beginCreatingSkill()`, `beginEditingSkill(_:)`, and a promote entry that
  presents the convert sheet. Saves route to the new `LibraryStore` methods.
- App views: new `Overlay/SkillEditorView.swift` (the editable Option-A twin of `ItemDetailView`),
  `ItemDetailView` gains the Edit affordance, `OverlayRootView` presents the editor layer,
  `PromptCardView` gains the skill ✎ and prompt ✦ actions, the `+` control becomes the two-item menu,
  and a small `ConvertPromptSheet`. A per-file text draft model backs the editor.
- `DebugHooks`: notifications to script open-editor / edit-field / save / create / promote for
  harness verification.

## Testing (swift-testing, temp dirs + temp `~/.claude/skills`)

- 🔬 **Kit unit:** `createSkill` writes pure frontmatter + sidecar + symlink, folder == slug(name),
  collisions suffix; `updateSkill` changes each field; **rename path** moves folder, removes old
  link, creates new link, keeps `id`, and on a foreign new-name collision skips the link but still
  renames the folder; `writeSkillFile` creates nested subfolders and refuses reserved/escaping paths;
  `renameSkillFile` / `deleteSkillFile` guard the same; `promotePromptToSkill` creates-from-content
  and removes the prompt (and the keep-original variant); concurrent authoring stays uncorrupted.
- 🎭 **Store behavioural:** create / update / promote reflect in `items` after refresh; self-write
  suppression holds; an external skill-folder add still live-reloads.
- 🎭 **App:** debug-harness scripts — edit→save updates the item, create→new card, promote→skill
  appears and the prompt is gone (verified via `dumpState`, since the snapshot hook hangs on the
  detail overlay — a known harness limitation from Layer B).
- 💨 **Smoke:** `swift build && swift test && make app`; create a skill in-app → it symlinks into
  `~/.claude/skills` and `claude` lists it; rename it → the symlink follows; add a file → it exists
  on disk under the skill folder.

## Phases

- **C0** — Kit authoring primitives + unit tests (create, update + rename, file ops, promote).
- **C1** — `LibraryStore` wrappers + behavioural tests.
- **C2** — `SkillEditorView` (editable detail) + edit-existing entry from the detail overlay.
- **C3** — Create-new-skill menu + convert-prompt-to-skill flow.
- **C4** — Full file ops: import from disk, subfolder creation, rename/delete, non-text handling.
- **C5** — Smoke (build/test/app, live symlink proof), README, memory.
