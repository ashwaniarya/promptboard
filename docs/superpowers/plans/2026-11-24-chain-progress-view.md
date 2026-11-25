# Chain Progress View Implementation Plan

📦 4 PRs across 3 phases (Kit 1, App 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ⌥/ chain row shows a segmented progress bar and, when selected, what ⏎ pastes next. The step list shows per-step status and restarts on ⌘R.

**Spec:** `docs/superpowers/specs/2026-11-24-chain-progress-view-design.md`. Every approved decision there is binding unless this plan says otherwise.

**Architecture:** One pure Kit view-model, `ChainProgressView`, turns `(chain, prompts, progressIndex)` into segment states, row tags and a next-step preview. It reuses `ChainStepList` for step resolution, so the "current step" rule lives in one place. The App target has no tests, so the App PRs only draw that view-model and route keys to `QuickInsertModel`. `saveProgress` stays the only writer of `chain-state.json`.

**Tech stack:** Swift 6 / SwiftPM, swift-testing (`@Test` / `#expect`), SwiftUI + AppKit (macOS 14). No new dependencies.

---

## Global constraints

- Branch: stack on `chains/progress-view` (cut from `chains/pr-9`). Land after the chain stack `chains/pr-1..9` merges. **Merge commits only, never squash a stack.** Never touch `main`.
- Baseline: `swift test` = 234 tests passing (measured 2026-11-24 on this branch). Every PR ends green; the count rises only by the tests it adds.
- Test command: `swift test 2>&1 | grep -E 'FAIL|error|passed|failed' | tail -n 40`.
- App build check: `swift build 2>&1 | tail -n 120` (expect `Build complete!`).
- **Anti-goal:** running, advancing or restarting a chain writes only `chain-state.json`. No `.md` file is written. The progress file shape stays `{"<chain uuid>": nextStepIndex}`.
- No animation. No clipboard tab, no ⇥ hint.
- Copy is exact: results footer `⏎ paste next · → open steps`; step list footer `⏎ paste and advance · ↑↓ pick · ⌘R restart · esc back`; selected row line `Next: <preview>`; done line `All N done · ⏎ restarts`; tags `now`, `linked`, `custom`, `missing, skipped`; header `step X of N` or `done`.
- No comments except a non-obvious *why*. Match the density of the file you edit.
- Tiers: **Unit** = pure Kit logic. **Behavioural** = Kit flows through the file system, or an App flow checked with a debug notification. **Smoke** = a real app run in a real text field.
- App verification (no test target): (1) the Kit tests for the same logic, (2) `swift build`, (3) a debug hook (app launched with `PROMPTBOARD_DEBUG=1`) that logs a `PromptBoardDebug …` line, read with `log stream --predicate 'eventMessage CONTAINS "PromptBoardDebug"' --style compact`. Post with:
  `xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.arya.PromptBoard.debug.<name>"), object: "<arg>", userInfo: nil, deliverImmediately: true)'`
- `.md` check: `find ~/Library/Application\ Support/PromptBoard/Library -name '*.md' -exec shasum {} + | shasum` gives the same value before and after a run.

## Review focus

1. **→ inside the search field.** → is intercepted only when no step list is open **and** the selected result is a chain. On a prompt row, → must still reach the text field and move the caret. Owner: Task 4.
2. **⌘R outside the step list.** ⌘R with the step list closed must pass through (return the event), never restart a chain and never be swallowed. Plain `r` and ⌘⇧R must type or pass through as today. Owner: Task 3.
3. **`debugPickStep` after ⏎ changes.** It calls `model.activate()` to open the list today. Once ⏎ pastes, it would paste instead. Task 4 switches it to `model.openSteps()`, or the existing `chainPick` hook silently breaks.
4. **Missing step at or after progress.** A deleted linked prompt at the stored index must not be "current" or the Next preview. Current moves to the next ready step. A chain whose only remaining steps are missing reads as done. Owner: Task 1 (tests `missingAtProgressIsNeverCurrent`, `trailingMissingStepsReadAsDone`).
5. **Long or blank custom first lines.** A custom step whose text starts with blank lines previews its first non-empty line. A 200-char line truncates to 60 characters ending in `…`. Owner: Task 1 (tests `previewSkipsLeadingBlankLines`, `previewTruncatesAtSixtyCharacters`).

## Open calls decided in this plan

1. **Bar look:** segment height 3 pt, gap 2 pt, corner radius 1.5 pt, segments share the row width equally. Done = `Color.green.opacity(0.85)`, current = the view's existing `accent`, upcoming = `.white.opacity(0.13)` (the border token), missing = `.white.opacity(0.06)`, 1 pt tall. Continuous bar (over 12 steps) = upcoming track with a green fill of width `completedCount / stepCount`.
2. **Preview truncation:** 60 characters, single line. Longer text = first 59 characters + `…`.
3. **⌘R asks no confirmation.**
4. **← does nothing new.** Not approved; ← stays with the text field.
5. **Footer visibility:** the results footer shows only while the selected result is a chain (the hints are chain keys). The step list footer always shows and replaces the header's `esc back`.
6. **⏎ on a done list or done row** restarts without pasting, as today; it routes through the same `restart()` as ⌘R.
7. `Segment` is a plain enum (`[ChainProgressView.Segment]`), not a struct with a nested `State`; a struct holding one field adds nothing.

## PR table

| # | Title | Scope | ~Lines | Depends on | Tests (tier) | Verify by |
|---|---|---|---|---|---|---|
| 1 | feat(kit): chain progress view-model | `ChainProgressView.swift` (new), `ChainStepList.progressIndex`, `ChainProgress.reset`, tests | 180 | chains/pr-9 | 14 Unit, 1 Behavioural | `swift test` |
| 2 | feat(app): chain row bar and Next line | `QuickInsertView.row`, `QuickInsertModel.progressView(for:)`, `DebugHooks.chainState` | 130 | 1 | 1 Behavioural (debug) | `swift build`; `chainState` log |
| 3 | feat(app): step list tags and ⌘R restart | `QuickInsertView` list + footer, `QuickInsertModel.restart()`, key monitor ⌘R, `DebugHooks.chainRestart` | 180 | 1 (parallel with 2) | 2 Behavioural (debug), 1 Smoke | `chainRestart` log; `.md` shasum unchanged |
| 4 | feat(app): ⏎ pastes next, → opens steps | `QuickInsertModel.activate/pasteNext/openSteps`, key monitor →, results footer, `debugPickStep` | 110 | 2, 3 | 2 Behavioural (debug), 1 Smoke | `insertFirstResult` advances; Smoke in a real text field |

Phases: **P0** = PR 1 (Kit) · **P1** = PRs 2, 3 (draw state, prerequisite P0) · **P2** = PR 4 (key change, prerequisite P1).

```
P0 Kit view-model -> P1 draw (parallel) -> P2 keys
 PR1 ---------------> PR2 (row bar) ------\
     \--------------> PR3 (list, ⌘R) -----+--> PR4 (⏎ paste next, →)
```

---

## Task 1 (PR 1) — Kit: `ChainProgressView` + `ChainProgress.reset`

**Prerequisite:** `chains/pr-9` (has `ChainStepList`, `ChainProgress`).

**Files:**
- Create: `Sources/PromptBoardKit/ChainProgressView.swift`
- Modify: `Sources/PromptBoardKit/ChainStepList.swift:15-33` (store `progressIndex`)
- Modify: `Sources/PromptBoardKit/ChainProgress.swift:17` (add `reset` next to `setIndex`)
- Create: `Tests/PromptBoardKitTests/ChainProgressViewTests.swift`
- Modify: `Tests/PromptBoardKitTests/ChainProgressTests.swift`

**Interfaces (produces):**
```swift
public struct ChainProgressView: Equatable, Sendable {
    public enum Segment: Equatable, Sendable { case done, current, upcoming, missing }
    public enum Tag: Equatable, Sendable { case now, linked, custom, missingSkipped }
    public static let continuousBarThreshold = 12
    public static let previewCharacterLimit = 60
    public let segments: [Segment]
    public let rowTags: [Tag]
    public let currentIndex: Int?
    public let nextPreview: String?
    public var stepCount: Int { get }          // chain.steps.count
    public var completedCount: Int { get }     // currentIndex ?? stepCount (positional)
    public var isEmpty: Bool { get }           // no ready steps
    public var isDone: Bool { get }            // !isEmpty && currentIndex == nil
    public var usesContinuousBar: Bool { get } // stepCount > continuousBarThreshold
    public init(chain: Chain, prompts: [Prompt], progressIndex: Int)
    public init(stepList: ChainStepList)
}
// ChainStepList gains:  public let progressIndex: Int
// ChainProgress gains:  public func reset(for chainID: UUID) throws   // setIndex(0, for:)
```

Rules: build from `ChainStepList(chain:prompts:progressIndex:)`; `currentIndex` = its initial `selectedIndex` (first ready step at or after `progressIndex`). Segment per step: `.missing` for a `.missing` row (any position), else `.done` before `currentIndex`, `.current` at it, `.upcoming` after; when done, every ready step is `.done`. Tags: `.now` at `currentIndex`, `.missingSkipped` for missing rows, else `.linked` / `.custom` from `chain.steps`. `nextPreview` = the current row's `title` (prompt title, or the custom step's first non-empty line, already computed by `ChainStepList`), truncated per open call 2; nil when done or empty. `ChainStepList.init` keeps its signature; it stores `progressIndex` as passed (unclamped value is fine, the caller already clamps).

- [ ] **Step 1: write the failing tests** (`ChainProgressViewTests`, helpers like `ChainStepListTests`: prompts `spec`, `plan`; `view(_ steps:, progress:)`). All **Unit** unless marked.
  - `freshChainFirstSegmentIsCurrent`: 3 steps, progress 0 → `segments == [.current, .upcoming, .upcoming]`, `completedCount == 0`, `currentIndex == 0`.
  - `middleProgressMarksDoneBeforeCurrent`: progress 2 → `[.done, .done, .current]`, `completedCount == 2`.
  - `finishedChainIsAllDone`: progress 3 → `[.done, .done, .done]`, `isDone`, `nextPreview == nil`, `completedCount == 3`.
  - `missingAtProgressIsNeverCurrent`: `[.linked(UUID()), .custom("b")]`, progress 0 → `[.missing, .current]`, `rowTags == [.missingSkipped, .now]`.
  - `trailingMissingStepsReadAsDone`: `[.custom("a"), .linked(UUID())]`, progress 1 → `isDone`, `segments == [.done, .missing]`.
  - `emptyChainHasNoPreviewAndIsNotDone`: only missing links → `isEmpty`, `!isDone`, `nextPreview == nil`.
  - `twelveStepsUseSegments` / `thirteenStepsUseContinuousBar`: `usesContinuousBar` false at 12, true at 13.
  - `previewOfLinkedStepIsPromptTitle`: `nextPreview == "Spec"`.
  - `previewSkipsLeadingBlankLines`: custom `"\n\nreview\nit all"` → `"review"`.
  - `previewTruncatesAtSixtyCharacters`: custom of 200 `"x"` → count 60, `hasSuffix("…")`; custom of exactly 60 `"x"` → unchanged.
  - `rowTagsMarkLinkedAndCustom`: progress 1 on `[spec, plan, custom]` → `[.linked, .now, .custom]`.
  - `stepListExposesProgressIndex`: `ChainStepList(..., progressIndex: 2).progressIndex == 2`, and `ChainProgressView(stepList:) == ChainProgressView(chain:prompts:progressIndex: 2)`.
  - In `ChainProgressTests`: `resetWritesZeroAndKeepsOtherChains` (**Unit**): set `a`=2, `b`=1, `reset(for: a)` → `index(a)==0`, `index(b)==1`.
  - In `ChainProgressTests`: `resetNeverWritesLibraryFiles` (**Behavioural**, `@MainActor`): `LibraryStore` on a temp dir, `addChain` with 2 custom steps, record `modificationDate` of every `.md` under `repository.libraryURL`, then `setIndex(1)`, `setIndex(2)`, `reset` → dates unchanged.
- [ ] **Step 2: run, expect FAIL** — `swift test --filter 'ChainProgressViewTests|ChainProgressTests' 2>&1 | grep -E 'FAIL|error|passed|failed' | tail -n 40` → `error: cannot find 'ChainProgressView' in scope`.
- [ ] **Step 3: implement** the interfaces above in the three Kit files.
- [ ] **Step 4: run the full suite** — test command → `Test run with 249 tests passed`.
- [ ] **Step 5: commit**
```bash
git add Sources/PromptBoardKit/ChainProgressView.swift Sources/PromptBoardKit/ChainStepList.swift Sources/PromptBoardKit/ChainProgress.swift Tests/PromptBoardKitTests/ChainProgressViewTests.swift Tests/PromptBoardKitTests/ChainProgressTests.swift
git commit -m "feat(kit): chain progress view-model"
```

---

## Task 2 (PR 2) — App: chain row bar and Next line

**Prerequisite:** Task 1.

**Files:**
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertModel.swift:37-42` (add `progressView(for:)` beside `stepList(for:)`)
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertView.swift:57-92` (`row(_:index:)`), new private `progressBar(_:)`
- Modify: `Sources/PromptBoardApp/DebugHooks.swift` (new `chainStateNotification`)

**Interfaces:**
- Consumes: `ChainProgressView(stepList:)`, `.segments`, `.usesContinuousBar`, `.completedCount`, `.stepCount`, `.nextPreview`, `.isDone`, `.isEmpty`.
- Produces: `func progressView(for chain: Chain) -> ChainProgressView` on `QuickInsertModel` (= `ChainProgressView(stepList: stepList(for: chain))`). Used by Tasks 3 and 4.

Row behaviour: chain row subtitle `"\(n) steps"` becomes `progressBar(view)`. Empty chain keeps today's dimmed row and `no steps` text (no bar, no line). Selected and non-empty: a second secondary line, `Next: \(nextPreview)` or, when done, `All \(stepCount) done · ⏎ restarts`. Bar look per open call 1. Prompt rows unchanged.

- [ ] **Step 1: add the debug hook** `com.arya.PromptBoard.debug.chainState`, arg = query. It sets the query, takes the first chain in `results`, and logs `PromptBoardDebug chainState chain=<title> segments=<d,c,u,m letters> continuous=<bool> next=<preview or ->`.
- [ ] **Step 2: implement** `progressView(for:)`, the bar and the Next line.
- [ ] **Step 3: build** — `swift build 2>&1 | tail -n 120` → `Build complete!`; test command → `249 tests passed`.
- [ ] **Step 4: verify (Behavioural, debug):** with a 3-step chain "Ship" at progress 1, post `chainState` with `ship` → log `segments=d,c,u ... next=Plan`. Open ⌥/, type `ship`: row shows 3 segments (green, accent, grey) and `Next: Plan` only on the selected row. Screenshot at `scale: 0.5` as layout proof.
- [ ] **Step 5: commit** — `git commit -m "feat(app): chain row bar and Next line"`.

---

## Task 3 (PR 3) — App: step list tags, header, footer, ⌘R restart

**Prerequisite:** Task 1. Independent of Task 2 (if Task 2 has not landed, add `progressView(for:)` here and drop it from Task 2 on rebase).

**Files:**
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertModel.swift:79-103` (`restart()`; `.restart` branch calls it)
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertController.swift:177-196` (key monitor)
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertView.swift:94-140` (`stepListView`, `stepRow`)
- Modify: `Sources/PromptBoardApp/DebugHooks.swift` (new `chainRestartNotification`)

**Interfaces:**
- Consumes: `ChainProgressView(stepList:)`, `.rowTags`, `.currentIndex`, `.completedCount`, `.isDone`; `ChainProgress.reset(for:)`; `ChainStepList.progressIndex`.
- Produces: `func restart()` on `QuickInsertModel`: no-op when `stepList == nil`; else `store.chainProgress.reset(for:)` (log on failure, as `saveProgress` does) and rebuild `stepList` from fresh progress, so step 1 is selected and the list stays open. Never returns text.

Key monitor: extract `let commandOnly = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command` before `assumeIsolated` (NSEvent is not Sendable). `case 15 where commandOnly && self.model.stepList != nil: self.model.restart(); return true`. Every other ⌘R / `r` falls to `default: return false`.

View: header = chain title, then `step \(completedCount + 1) of \(stepCount)` or `done` (replaces `esc back`). Row = numbered circle (`Image(systemName: "checkmark.circle.fill")` when its segment is `.done`, else the number in a 16 pt circle stroke), step text, trailing tag text from `rowTags` per Global constraints copy. Done rows `opacity(0.5)`; `now` row tag in `accent`; arrow selection keeps today's accent background. Drop the old `done · ⏎ restarts` line (header says `done`). Footer = the exact step list copy, `.font(.system(size: 10)).foregroundStyle(.tertiary)`.

- [ ] **Step 1: add the debug hook** `com.arya.PromptBoard.debug.chainRestart`, arg = query: open the first chain's step list (`model.query = query`, `selectedIndex = 0`, then today's `activate()` path), call `model.restart()`, log `PromptBoardDebug chainRestart chain=<title> index=<stored index> selected=<stepList.selectedIndex> open=<stepList != nil>`.
- [ ] **Step 2: implement** `restart()`, the ⌘R case and the list view.
- [ ] **Step 3: build + tests** — `Build complete!`; `249 tests passed`.
- [ ] **Step 4: verify (Behavioural, debug):** advance "Ship" to done with `chainPick` (`ship|2`), then post `chainRestart` `ship` → `index=0 selected=0 open=true`, and no paste happened (no `inserting` line).
- [ ] **Step 5: verify (Behavioural, debug):** record the `.md` shasum, run `chainPick` ×3 and `chainRestart`, shasum again → same value.
- [ ] **Step 6: Smoke:** open ⌥/ in TextEdit, `ship` → ⏎ (opens list at this point) → ⌘R restarts and nothing is typed; with the list closed, ⌘R and `r` behave as before (Review focus 2).
- [ ] **Step 7: commit** — `git commit -m "feat(app): step list tags and ⌘R restart"`.

---

## Task 4 (PR 4) — App: ⏎ pastes next, → opens steps

**Prerequisite:** Tasks 2 and 3 (the Next line and ⌘R must exist before ⏎ stops opening the list, or a user loses the only way to see steps).

**Files:**
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertModel.swift:79-103`
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertController.swift:56-66` (`debugPickStep`), key monitor
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertView.swift` (results footer)

**Interfaces:**
- Consumes: `stepList(for:)`, `ChainStepList.activate()`, `restart()` logic, `saveProgress(_:for:)`.
- Produces on `QuickInsertModel`:
  - `func pasteNext(for chain: Chain) -> String?` — `.paste(text, next)` → `saveProgress(next)`, return text; `.restart` → `saveProgress(0)`, return nil; `.nothing` → nil. The list stays closed.
  - `func openSteps() -> Bool` — when `stepList == nil` and `selected` is a non-empty chain, open its list and return true; else false.
  - `activate()`: `.chain(let chain)` arm becomes `return pasteNext(for: chain)`. The step-list branch is unchanged.

Key monitor: `case 124 where self.model.openSteps(): return true` (otherwise the event passes, so the caret still moves; Review focus 1). `debugPickStep` calls `model.openSteps()` instead of relying on `activate()` to open the list (Review focus 3). Results footer: the exact results copy, shown only while `model.selected` is a chain.

- [ ] **Step 1: implement** `pasteNext`, `openSteps`, the `activate()` arm, key 124, `debugPickStep`, footer.
- [ ] **Step 2: build + tests** — `Build complete!`; `249 tests passed`.
- [ ] **Step 3: verify (Behavioural, debug):** reset "Ship", post `insertFirstResult` `ship` twice → logs paste step 1 then step 2; `chainState ship` → `segments=d,d,c`.
- [ ] **Step 4: verify (Behavioural, debug):** `chainPick` `ship|0` still opens the list and pastes step 1 (proves Review focus 3).
- [ ] **Step 5: Smoke:** in TextEdit, ⌥/ `ship` ⏎ ×3 pastes steps 1-3 one per press; the row then reads `All 3 done · ⏎ restarts`; ⏎ restarts without typing; → opens the list; → on a prompt row moves the caret in the query. `.md` shasum unchanged across the run.
- [ ] **Step 6: commit** — `git commit -m "feat(app): ⏎ pastes next, → opens steps"`.
