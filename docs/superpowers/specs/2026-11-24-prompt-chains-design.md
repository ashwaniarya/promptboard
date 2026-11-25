# Design — Prompt Chains

Status: proposed 2026-11-24 · Scope: new library item kind + quick-insert (⌥/) stepping · Plan: none yet

## Why

Arya runs multi-turn AI work in a fixed order (spec → plan → build → review) and today pastes each
prompt by hand, hunting for the next one every turn. A **chain** plans that sequence ahead: ⌥/
pastes the next step, one per AI turn.

## Locked decisions

1. **A chain is a topic with ordered steps.** Each step is either a **linked** library prompt (by
   prompt `id`, so edits to that prompt flow into the chain) or **custom** text written inside the chain.
2. **One `.md` file per chain** (Approach A). Frontmatter carries `kind: chain` plus the usual
   `id`/`title`/`createdAt`/`updatedAt`; the body is the ordered step list.
3. **Running:** ⌥/ on a chain pastes its next step. The popup shows the step list with the next step
   highlighted; arrow keys pick any step. **Picking step N pastes it and progress moves to N+1** (the
   chain follows the jump).
4. **Chains appear in ⌥/ search** alongside prompts.
5. **Chains are built and edited in the board (⌥Space):** add step (pick existing prompt or write
   custom), reorder, remove.
6. **Progress lives in a separate state file**, keyed by chain id. Running a chain never touches a
   chain `.md` or its `updatedAt`.
7. **Deleted linked prompt:** the step shows as "missing" and is skipped when advancing.
8. **After the last step** the popup shows "done"; Enter restarts the chain.

## Approaches

| | Approach | Verdict |
|---|---|---|
| A | One `.md` per chain, `kind: chain`, step list in body | **Chosen** — links by id, files stay source of truth, MCP and watcher see it |
| B | Folder of numbered files | Rejected — no links, and folder-as-chain clashes with folder-as-group (folder-structure design) |
| C | `chains.json` | Rejected — MCP and the directory watcher are blind to it |

## Anti-goal

Running a chain must not modify any prompt file. Only the state file is written on a run.

## Non-goals (v1)

Clipboard history (separate design) · chains inside chains · variables · MCP exposure of chains (read or write).

## What it touches (verified against current code)

- `Sources/PromptBoardKit/Prompt.swift:3-25` — `Prompt` has no `kind`. A chain should be a new type
  (`Chain`) rather than a field on `Prompt`, so prompt consumers stay unchanged.
- `Sources/PromptBoardKit/LibraryRepository.swift:262-277` (`readPrompt`) — parses any `.md` that has
  a valid `id`; it ignores unknown frontmatter, so **a chain file would load as a plain prompt today**.
  `load()` (`:50-65`) must branch on `kind: chain` first, otherwise chains leak into the prompt list
  and the ⌥/ prompt results. This is the one existing behavior that changes.
- `LibraryRepository.swift:279-291` (`writePrompt`) — writes fixed fields via `Frontmatter.render`;
  a parallel `writeChain` adds `kind: chain`. `readPrompt` stays unchanged except the guard above.
- `Sources/PromptBoardKit/LibraryStore.swift:228-234` — the directory watcher already reloads on file
  changes; chain edits ride on it. The state file lives **outside** the watched prompt directory, so
  stepping never triggers a reload.
- `Sources/PromptBoardKit/PromptFilter.swift:43-62` (`quickInsertResults`) — typed as
  `[Prompt] -> [Prompt]`, tiered alias/title/content ranking. Chains need the same ranking over a
  mixed result type; the ranking is reused, the signature changes.
- `Sources/PromptBoardApp/Overlay/QuickInsertModel.swift:21-29` — `results` is `[Prompt]` capped at 8;
  `selected` returns a `Prompt`. Needs a mixed result (prompt | chain) and, when a chain is selected,
  a step-list mode with its own `selectedIndex`.
- `Sources/PromptBoardApp/Overlay/QuickInsertController.swift:35-45,60-69` — `insert` and
  `performInsert` already paste a plain `String`. A chain step resolves to a string (linked content or
  custom text), so the paste path is reused as is; only the "what to paste, then advance progress"
  step is new.
- `Sources/PromptBoardApp/Overlay/QuickInsertView.swift:55` (`row`) — gains a chain row and the
  step-list rendering (next highlighted, "missing" and "done" states).
- Board UI (⌥Space): a chain editor sheet (add step, reorder, remove). Exact UI is left to the builder.

## Claude's calls (owner may overrule)

1. **Library type:** chain is a new `.chain` case in `LibraryEntry`
   (`Sources/PromptBoardKit/LibraryEntry.swift`), same pattern as `.skill`; update its `Kind` and every switch.
2. **Empty chain:** 0 steps, or all steps missing, shows in ⌥/ greyed as "no steps" and cannot be pasted.
3. **Progress file:** `~/Library/Application Support/PromptBoard/chain-state.json` (outside the watched
   prompts dir), shape `{chainId: nextIndex}`. Clamp the index if the chain shrinks; prune unknown ids on load.
4. **Location:** chains live in prompts-dir folders; group comes from the folder path, like prompts.
5. **Step syntax in body:** `- @<prompt-uuid>` for a linked step; a fenced ``` block for a custom step
   (multi-line safe). Must round-trip through `Frontmatter` and stay human-editable.
6. **Deleted linked prompt:** no warning; the step shows "missing".
7. **Popup step list:** Esc returns to search results.
8. **MCP:** chains are not exposed in v1; exclude them from `list_prompts` so they never leak as prompts.

## Testing

- 🔬 **Unit:** chain parse/render round-trip; `load()` routes `kind: chain` away from prompts;
  next-step resolution skips missing linked prompts; wrap/restart after last step; mixed ranking.
- 🎭 **Behavioural:** ⌥/ pastes step 1, then 2, in order; editing a linked prompt changes the next
  paste; arrow pick of step N pastes it and moves progress to N+1; deleting a linked prompt shows "missing"; Enter on
  "done" restarts. Verify via debug notifications, as for `debugInsertFirst` (`QuickInsertController.swift:47`).
- 🔬 **Anti-goal check:** after a full chain run, every prompt and chain file is byte-identical.
- 💨 **Smoke:** real app — build a 3-step chain, run it in a real AI chat, one step per turn.

## Phases

- **C0** — Kit: `Chain` type, `.md` read/write, `load()` split + tests
- **C1** — Kit: progress state file + next-step resolution + tests
- **C2** — Kit: mixed ⌥/ ranking + tests
- **C3** — ⌥/ popup: chain rows, step list, paste-and-advance
- **C4** — Board: chain editor (add, reorder, remove)
- **C5** — Smoke, docs, memory
