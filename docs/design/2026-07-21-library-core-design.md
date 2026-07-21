# Design — Folder-Based Library Core (Prompts + Skills)

Status: approved 2026-07-21 · Scope: Layer A (data foundation)

## Why

PromptBoard is a prompt box over a single `prompts.json`. We are evolving it into a
**prompt *and skill* manager**: a card is either a plain prompt or a Claude Agent Skill
(a `SKILL.md` + supporting files), organized in groups, rendered as markdown, and usable
directly by Claude Code. This document is the durable design; the full vision ships in four
layers, built foundation-first:

- **A — Library core (this doc):** folder-based store, prompts + skills, groups, symlink, CLI/MCP.
- **B — Redesigned board:** fixed-height cards, markdown render, icon column toggle, infinite scroll.
- **C — Skill + file editor:** edit `SKILL.md`, frontmatter, add/rename files, create new skills.
- **D — Cursor quick-insert:** slash-command search popup at the caret.

Layers B/C/D are out of scope here. Layer A keeps the app functional with only minimal card changes.

## Locked decisions

1. Redesign the ⌥Space overlay in place (not a new window); add cursor popup + skill editor later.
2. Items are **prompts** (`.md`) and **skills** (Agent Skills `SKILL.md` folders), in **groups**.
3. **Files are the source of truth** — frontmatter metadata, no central index; the library is scanned.
4. The **PromptBoard library folder is the source of truth**; skills are **symlinked** into
   `~/.claude/skills` (live for Claude Code) and remain the CLI/MCP backend.
5. Render markdown in the UI; **copy the raw markdown**.

## On-disk contract

```
~/Library/Application Support/PromptBoard/
├── prompts.json                      # LEGACY — migrated once, kept as backup, never deleted
└── Library/
    ├── .promptboard.lock             # flock sidecar, stable inode
    ├── prompts/<slug>.md             # one prompt each: frontmatter + markdown body
    └── skills/<name>/                # one skill each (folder name == skill name)
        ├── SKILL.md                  # spec-pure: name + description + body
        ├── .promptboard.json         # sidecar: PromptBoard bookkeeping (see below)
        └── …supporting files…
```

**Prompt** `prompts/<slug>.md` — everything in frontmatter (it is our format):
```markdown
---
id: <uuid>              # stable identity; the slug/filename may change on rename
title: Code review
group: Coding            # optional; absent → "Ungrouped"
createdAt: <iso8601 ms>
updatedAt: <iso8601 ms>
---
Review the diff for: …
```

**Skill** `skills/<name>/SKILL.md` — kept exactly to the Agent Skills spec so Claude Code loads it
cleanly (verified: real skills in `~/.claude/skills` carry only `name` + `description`):
```markdown
---
name: trello-card-reader
description: Read and summarize a Trello card from a URL
---
# Trello card reader …
```
PromptBoard's own metadata lives in a **sidecar** `skills/<name>/.promptboard.json`
(`{ id, group, createdAt, updatedAt }`) — never in `SKILL.md`. This keeps skills portable and
avoids any risk of the loader rejecting unknown frontmatter keys. `id` is stable across renames.

- **Slug/name** derived from the title (kebab-case); collisions get a `-2`/`-3` suffix. APFS is
  case-insensitive, so de-dup is case-insensitive.
- **Groups** are a frontmatter/sidecar field only; the sidebar is the distinct values scanned across items.

## Symlink contract (`~/.claude/skills`)

Each `Library/skills/<name>/` is symlinked to `~/.claude/skills/<name>`.

- Create `~/.claude/skills` if missing; create/repair the link on skill add/rename; remove on delete.
- **Never touch a path we did not create.** If `~/.claude/skills/<name>` already exists as a real
  directory or a foreign symlink, skip and warn — never clobber. (Real user skills already live there.)
- We only ever remove/replace a symlink whose resolved target points inside our library.
- Codex and other agents reach items through the MCP server, not this Claude-specific folder.

## Component map (evolution, not rewrite)

- **Kit model:** `Prompt` gains `group`; new `Skill` + `SkillFile`; `LibraryItem { .prompt | .skill }`
  with shared `id`/`title`/`group`/`updatedAt`/`kind`. New `Frontmatter` (parse/render) and `Slug`.
- **`PromptRepository` → `LibraryRepository`:** same flock RMW / atomic-write / quarantine discipline,
  now scanning `prompts/` + `skills/`, parsing frontmatter + sidecars, managing symlinks, with a
  one-time `prompts.json` → `.md` migration (backs up, never deletes). One malformed item is skipped
  and logged, never fatal.
- **`PromptStore` → `LibraryStore`:** `@MainActor @Observable` cache of `[LibraryItem]` + groups;
  live-reload via directory watch + content-diff self-write suppression; symlink orchestration.
- **CLI + MCP:** `list`/`get` cover both types; prompt CRUD unchanged in shape; add `import-skill` +
  `relink`; MCP gains `list_skills`/`get_skill`. Skill authoring lands in Layer C.

## Testing

Same tiers as the rest of the project (swift-testing, temp dirs / temp `$HOME`):

- 🔬 Unit: frontmatter round-trip; slug + collision; prompt CRUD file contents; skill read/import;
  legacy migration + backup; symlink create/remove/no-clobber; malformed-item resilience; concurrency.
- 🎭 Behavioural: `LibraryStore` live-reload for both types; symlink visibility; CLI both-type list.
- 💨 Smoke: `swift build && swift test && make app`; migrate a copy of the real `prompts.json`; a real
  skill shows up live in `~/.claude/skills`.
