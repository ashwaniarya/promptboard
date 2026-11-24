# Design — Chain Progress View

Status: proposed 2026-11-24 · Scope: quick-insert (⌥/) chain rows and step list · Builds on: `2026-11-24-prompt-chains-design.md` (branch `chains/pr-9`)

## Intent

Today a chain row only says "N steps", and its progress is visible only after opening the step list. Show where a chain stands directly in the results, and make restart a deliberate key.

## Goals

- Chain row shows a segmented progress bar, one segment per step.
- The selected chain row shows one extra line: what ⏎ will paste next.
- Step list shows per-row status (done / now / linked / custom / missing) and has a restart key.
- Footer hints match the keys that actually work.

## Non-goals / anti-goals

- Running or restarting never writes any `.md` file. Progress lives only in `chain-state.json`.
- No animation. No clipboard tab and no ⇥ hint until the clipboard design is built.
- No change to the chain file format or the progress file shape (`{"<chain uuid>": nextStepIndex}`).

## Approved design (mockup approved by Arya)

- **Results row:** the "step X of N" text becomes a segmented bar. Done = success green, current = accent, upcoming = neutral border, missing linked step = dim hairline. Over 12 steps: one continuous proportional bar, no segments.
- **Selected chain row only:** a secondary line `Next: <step preview>`. Linked step shows the prompt title; custom step shows its first line, truncated. Done chain: bar all green, line `All N done · ⏎ restarts`.
- **Keys, results:** ⏎ pastes the next step and advances. → opens the step list.
- **Step list:** header = chain title + `step X of N` (or `done`). Each row = numbered circle (check icon when done), step text, tag: `now` for current, `linked` / `custom` otherwise, `missing, skipped` for a deleted linked prompt. Done rows muted, current row highlighted.
- **⌘R in the step list** restarts the chain (progress to 0).
- **Footers:** results `⏎ paste next · → open steps`; step list `⏎ paste and advance · ↑↓ pick · ⌘R restart · esc back`.

## Behaviour details

- Current step = first ready step at or after the stored index (same rule as `ChainStepList.init`). Done = index of a ready step before it, or all steps when the chain is done.
- Missing steps count as upcoming/done by position, drawn dim, never "current".
- Empty chain (no ready steps) keeps today's dimmed row and "no steps"; no bar, no Next line.
- ⌘R on a done list restarts and keeps the list open with step 1 selected. ⌘R never pastes.
- Segment threshold: `steps.count > 12` selects the continuous bar.

## Conflicts with current code

- Today ⏎ on a chain row **opens the step list** (`QuickInsertModel.swift:93-95`) and → is unhandled (`QuickInsertController.swift:184-190`). The approved design changes ⏎ to paste-next and moves "open steps" to → (key code 124). This is a deliberate behaviour change and gets its own PR.
- `ChainStepList.Row` (`.ready` / `.missing`) has no linked/custom tag and no current marker; the view-model below supplies both so the existing enum stays.
- The step list's `selectedIndex` follows arrow picks, so it is not "current". Current comes from stored progress, not selection.

## Kit vs App split

**Kit (`PromptBoardKit`), pure and unit-testable**
- New `ChainProgressView` in `Sources/PromptBoardKit/ChainProgressView.swift`: `init(chain: Chain, prompts: [Prompt], progressIndex: Int)`.
  - `segments: [Segment]` with `Segment.State` = `.done | .current | .upcoming | .missing`.
  - `nextPreview: String?` (nil when done or empty), `isDone`, `completedCount`, `stepCount`, `usesContinuousBar`.
  - `rowTags: [Tag]` (`.now | .linked | .custom | .missingSkipped`) for the step list.
- Extend `ChainStepList` (`ChainStepList.swift:3`): expose `progressIndex` so the list header and row states use stored progress, not selection.
- Add `ChainProgress.reset(for:)` (`ChainProgress.swift:17` sibling, thin wrapper over `setIndex(0, ...)`).

**App (`PromptBoardApp/Overlay`)**
- `QuickInsertModel`: `pasteNext(for:)` used by ⏎ on a chain row; `openSteps()` for →; `restart()` for ⌘R, replacing the internal `.restart` branch of `activate()` (`:86-89`). `saveProgress` (`:111`) stays the only writer.
- `QuickInsertController.installKeyMonitor` (`:177`): add → (124) and ⌘R (keyCode 15 with `.command`); both ignored outside their mode.
- `QuickInsertView`: `row(_:index:)` (`:57`) draws the bar and Next line; `stepListView` (`:94`) / `stepRow` (`:116`) draw circles and tags; footer text per mode.

## Tests

| Tier | Test |
|---|---|
| Unit | `ChainProgressView` segment states: start, middle, done, missing step, empty chain |
| Unit | `usesContinuousBar` at 12 vs 13 steps |
| Unit | `nextPreview`: linked title, custom first line, truncation, nil when done |
| Unit | `ChainProgress.reset` writes 0 and leaves other chains untouched |
| Behavioural | ⏎ on chain row pastes next step and stores index+1; → opens list; ⌘R in list sets index 0 without pasting |
| Behavioural | No `.md` file mtime changes after paste, advance, restart |
| Smoke | `PromptBoardDebug` notifications: open ⌥/, chain row shows bar + Next, ⏎ advances, ⌘R restarts |

## PR slicing

📦 4 PRs, stacked, foundational first. Land after the chain stack (`chains/pr-1..9`) merges.

| # | Title | Scope | ~Lines | Depends on | Tests (tier) | Verify by |
|---|---|---|---|---|---|---|
| 1 | feat(kit): chain progress view-model | `ChainProgressView.swift`, `ChainProgress.reset` | ~150 | chains/pr-9 | Unit | `swift test` |
| 2 | feat(app): chain row bar and Next line | `QuickInsertView` row | ~120 | 1 | Behavioural | debug notifications, row state |
| 3 | feat(app): step list tags and ⌘R restart | `QuickInsertView` list, `QuickInsertModel`, key monitor, footers | ~180 | 1 | Behavioural, Smoke | ⌘R restarts, `.md` mtimes unchanged |
| 4 | feat(app): ⏎ pastes next, → opens steps | `QuickInsertModel.activate`, key monitor, results footer | ~100 | 2, 3 | Behavioural, Smoke | ⏎ advances in a real text field |

PRs 2 and 3 are independent of each other and can run in parallel.

## Open calls (builder's call)

- Exact segment size, gap and bar height; accent vs success green tokens.
- Preview truncation length (suggest ~60 chars, single line).
- Whether ⌘R asks for confirmation (suggest no; restart is cheap and reversible by picking a step).
- Whether ← also closes the step list (suggest yes, mirrors →).
