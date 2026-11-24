# Prompt Chains Implementation Plan

📦 9 PRs across 6 phases (Kit 6, App 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A chain is a library item with ordered steps (linked prompt or custom text). ⌥/ pastes its next step, one per AI turn. Progress lives in a state file that never touches library files.

**Spec:** `docs/superpowers/specs/2026-11-24-prompt-chains-design.md`. Every locked decision and every "Claude's call" there is binding unless this plan says otherwise.

**Architecture:** `Chain` is a new Kit type and a new `.chain` case in `LibraryEntry`. It is stored as `prompts/<folder>/<slug>.md` with `kind: chain` in the frontmatter and a step list in the body. `load()` routes `kind: chain` files away from prompts. Two pure Kit types hold the run logic: `ChainProgress` (the state file) and `ChainStepList` (step resolution and keyboard navigation). The App target has no tests, so all logic that can break lives in Kit. The App PRs only render state and call Kit.

**Tech stack:** Swift 6 / SwiftPM, swift-testing (`@Test` / `#expect`), SwiftUI + AppKit (macOS 14). No new dependencies.

---

## Global constraints

- Branch: stack every PR on `feature/prompt-chains`. **Merge commits only, never squash a stack.**
- Baseline: `swift test` = 182 tests passing (measured 2026-11-24). Every PR ends green, with the count going up by the tests it adds.
- Test command (filtered): `swift test 2>&1 | grep -E 'FAIL|ERROR|passed|failed' | tail -n 80`.
- Build check for App PRs: `swift build 2>&1 | tail -n 120` (expect `Build complete!`).
- **Anti-goal:** running a chain writes only `chain-state.json`. No prompt or chain `.md` is written, and no `updatedAt` changes.
- **Feature flag:** `Constants.chainsEnabled` reads `UserDefaults.standard.bool(forKey: "chainsEnabled")` (default false). While it is false, chains are hidden from the board and from ⌥/. To verify PRs 7 and 8 by hand, turn it on with `defaults write com.arya.PromptBoard chainsEnabled -bool true`. PR 9 deletes the flag.
- No comments except a non-obvious *why*. No docstrings. Match the density of the file you are editing.
- Tiers: **Unit** = pure Kit logic. **Behavioural** = Kit flows through `LibraryStore` or the file system, or an App flow checked with a debug notification. **Smoke** = a real app run before ship.
- App verification (no test target): (1) the Kit tests for the same logic, (2) `swift build`, (3) a debug notification that logs a `PromptBoardDebug …` line, read back with `log stream --predicate 'eventMessage CONTAINS "PromptBoardDebug"' --style compact`. Post with:
  `xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.arya.PromptBoard.debug.<name>"), object: "<arg>", userInfo: nil, deliverImmediately: true)'`

## Review focus

1. `LibraryEntry.Kind` gains a third case. `treeRoot(for:)` (`LibraryRepository+Folders.swift:8`) is currently `kind == .prompt ? prompts : skills`, so a chain would land in the **skills** tree. Flip it to `kind == .skill ? skills : prompts`.
2. Today, a hand-written chain file loads as a prompt **and gets exported as a skill** to Claude Code and Codex (`reconcileSync` iterates `.prompt`). PR 2 closes both leaks.
3. `findPromptFile` and `readPrompt` must never return a chain, so `updatePrompt`, `deletePrompt`, `movePrompt` and `promotePromptToSkill` cannot rewrite a chain as a prompt.
4. The state file sits at `<data dir>/chain-state.json`. That is outside `Library/prompts`, so stepping through a chain never fires the directory watcher.

## Claude's calls made in this plan (owner may overrule)

1. **Enter on a chain row opens its step list.** The next step is highlighted, and a second Enter pastes it. Esc goes back to the results.
2. **Enter on "done" resets progress to 0 without pasting.** Step 1 is then highlighted and Enter pastes it.
3. **Custom-step fence:** a custom step uses a run of backticks one longer than the longest run inside its text (at least 3). A fence that is never closed keeps the rest of the body as one custom step, so no user text is lost.
4. **Ranking text for a chain:** its title, plus the joined text of its custom steps. Linked prompt content is not searched.
5. **Reorder:** up/down buttons in the editor. Drag to reorder is not in v1.
6. **CLI:** `promptboard list` shows chains (`kind: chain`). MCP still hides them, because `PromptToolbox.loadPrompts` already filters on `kind == .prompt`.

## PR table

| # | Title | Scope | ~Lines | Depends on | Tests (tier) | Verify by |
|---|---|---|---|---|---|---|
| 1 | Kit: `Chain` model + body codec | `Chain.swift` (new), `ChainModelTests.swift` (new) | 150 | — | 7 Unit | `swift test --filter ChainModelTests` |
| 2 | Kit: `.chain` library entry + `load()` routing | `LibraryEntry`, `LibraryRepository` (load/readPrompt/readChain/writeChain), `+Folders` treeRoot, `LibraryStore` signature, `PromptFilter.filter(items)`, CLI `Commands`, App exhaustive switches + flag | 190 | 1 | 6 Unit, 1 Behavioural | `swift test`; `swift build`; `promptboard list --type chain` on a hand-made file |
| 3 | Kit: chain CRUD in repository + store | `LibraryRepository+Chains.swift` (new), access changes in `LibraryRepository.swift`, `LibraryStore` add/update/delete/move routing, CLI `Support` error arm | 220 | 2 | 6 Unit, 2 Behavioural | `swift test --filter ChainRepositoryTests` |
| 4 | Kit: `ChainProgress` state file | `ChainProgress.swift` (new), `LibraryRepository.chainStateURL`, `LibraryStore.chainProgress` + prune on launch | 170 | 3 | 7 Unit, 1 Behavioural | `swift test --filter ChainProgressTests` |
| 5 | Kit: `ChainStepList` resolution + navigation | `ChainStepList.swift` (new), tests | 200 | 1 (parallel with 2–4) | 11 Unit, 1 Behavioural (anti-goal) | `swift test --filter ChainStepListTests` |
| 6 | Kit: mixed ⌥/ ranking | `PromptFilter.quickInsertResults(_ entries:)` | 120 | 2 | 5 Unit | `swift test --filter PromptFilterTests` |
| 7 | ⌥/ popup: chain rows, step list, paste-and-advance (flagged) | `QuickInsertModel`, `QuickInsertView`, `QuickInsertController`, `DebugHooks`, drop old `[Prompt]` ranking overload | 260 | 4, 5, 6 | Kit tests from 5/6 + 3 Behavioural (debug) | `swift build`; debug `insertFirstResult`, `chainPick` with flag on |
| 8 | Board: chain editor sheet (unwired) | `ChainEditorView.swift` (new), `AppState` chain editor mode, `OverlayRootView` layer, `DebugHooks.newChain` | 280 | 3 | Kit tests from 3 + 2 Behavioural (debug) | `swift build`; debug `newChain` + `dumpItems` |
| 9 | Wire up: remove flag, New chain menu, card + detail, README | `Constants`, `QuickInsertModel`, `AppState.visibleItems`, `OverlayRootView` menu, `PromptCardView`, `ItemDetailView`, `README.md` | 150 | 7, 8 | 1 Smoke + Behavioural re-run | Smoke run (Task 9) |

Phases: **C0** = PRs 1–2 · **C1** = PRs 3–4 · **C2** = PRs 5–6 · **C3** = PR 7 · **C4** = PR 8 · **C5** = PR 9.

```
C0 model/parse  -> C1 repo/store/state -> C2 run logic + ranking -> C3 popup -> C4 editor -> C5 wire
 PR1 -> PR2 -------> PR3 -> PR4 ------------------------------------\
   \---------------------------------> PR5 (parallel) ---------------> PR7 ---\
           PR2 ----------------------> PR6 -----------------------------/      > PR9
                     PR3 ----------------------------------------------> PR8 -/
```

---

## Task 1 (PR 1) — Kit: `Chain` model + body codec

**Prerequisite:** none.

**Files:**
- Create: `Sources/PromptBoardKit/Chain.swift`
- Create: `Tests/PromptBoardKitTests/ChainModelTests.swift`

**Interfaces:**
```swift
public struct Chain: Identifiable, Codable, Equatable, Hashable, Sendable {
    public enum Step: Codable, Equatable, Hashable, Sendable {
        case linked(promptID: UUID)
        case custom(text: String)
    }
    public let id: UUID
    public var title: String
    public var steps: [Step]
    public var group: String?
    public let createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), title: String, steps: [Step], group: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date())
}

public enum ChainBody {
    public static func render(_ steps: [Chain.Step]) -> String
    public static func parse(_ body: String) -> [Chain.Step]
}
```
Body syntax: a linked step is one line, `- @<UUID>`. A custom step is a backtick fence on its own line, then the text, then the same fence. Steps are separated by one blank line. `parse` ignores any other line and any `- @` line whose UUID is invalid. `render` trims leading and trailing newlines from custom text.

- [ ] **Step 1: write the failing tests (all Unit)**
  - `renderParseRoundTripsMixedSteps`: `[.linked(a), .custom("Write the spec\n\nThen stop."), .linked(b)]` → `parse(render(x)) == x`.
  - `renderWritesHumanEditableSyntax`: `render([.linked(id)]) == "- @\(id.uuidString)"`; `render([.custom("hi")]) == "```\nhi\n```"`.
  - `customStepContainingBackticksUsesLongerFence`: text `"use ```swift``` here"` round-trips, and the rendered output contains `"````\n"`.
  - `parseIgnoresProseAndInvalidLinks`: `"intro\n- @not-a-uuid\n- @\(id)"` → `[.linked(id)]`.
  - `unclosedFenceKeepsRestAsCustomStep`: `"```\nline one\nline two"` → `[.custom("line one\nline two")]`.
  - `parseEmptyBodyGivesNoSteps`: `parse("") == []`.
  - `stepsSurviveFrontmatterRoundTrip`: `Frontmatter.parse(Frontmatter.render(fields: [("kind","chain")], body: ChainBody.render(x))).body` parsed back `== x`.
- [ ] **Step 2:** `swift test --filter ChainModelTests` → FAIL (`cannot find 'ChainBody'`).
- [ ] **Step 3:** implement `Chain.swift`.
- [ ] **Step 4:** `swift test --filter ChainModelTests` → 7 passed. Full suite → 189 passed.
- [ ] **Step 5:** commit `feat(kit): Chain model and step body codec`.

## Task 2 (PR 2) — Kit: `.chain` library entry + `load()` routing

**Prerequisite:** PR 1 (`Chain`, `ChainBody`).

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryEntry.swift` (case, `Kind.chain`, every computed var, Codable arms)
- Modify: `Sources/PromptBoardKit/LibraryRepository.swift:50-70` (`load`), `:262` (`readPrompt` guard), add `readChain` / `writeChain`
- Modify: `Sources/PromptBoardKit/LibraryRepository+Folders.swift:8` (`treeRoot`, see Review focus 1)
- Modify: `Sources/PromptBoardKit/LibraryStore.swift:293` (`signature`: `"c:<id>:<updatedAt>:<steps.count>"`)
- Modify: `Sources/PromptBoardKit/PromptFilter.swift:12` (`filter(_ items:)`: a chain matches on title or custom step text)
- Modify: `Sources/PromptBoardCLI/Commands.swift:23` (validate message `prompt, skill or chain`), `:72` (`Get`: a chain prints `ChainBody.render(steps)`, or JSON with `--json`)
- Modify: `Sources/PromptBoardApp/Constants.swift` (add `chainsEnabled`, see Global constraints)
- Modify: `Sources/PromptBoardApp/AppState.swift:61` (`visibleItems` drops `.chain` while the flag is off), `:135` (`copyToClipboard`: a chain copies `ChainBody.render`)
- Modify: `Sources/PromptBoardApp/Overlay/ItemDetailView.swift:94,168` (chain arm: `ChainBody.render` as text, enough for now)
- Create: `Tests/PromptBoardKitTests/ChainRepositoryTests.swift`

**Interfaces:**
```swift
case chain(Chain)                                   // LibraryEntry
case chain                                          // LibraryEntry.Kind, rawValue "chain"
// previewText for a chain: "\(steps.count) steps"
private func readChain(at url: URL) -> Chain?       // nil unless fields["kind"] == "chain" and id is valid
func writeChain(_ chain: Chain, to url: URL) throws // fields: id, kind, title, createdAt, updatedAt; body ChainBody.render
```
`load()`: for each `.md`, try `readChain` first, then `readPrompt`, else add it to `skippedPaths`. `readPrompt` returns nil when `fields["kind"] == "chain"`.

- [ ] **Step 1: write the failing tests.** Write a raw chain file by hand (the documented format): `---\nid: <uuid>\nkind: chain\ntitle: Ship\n…---\n\n- @<promptID>\n\n```\nreview it\n```\n`.
  - Unit `loadRoutesChainFileToChainEntry`: file at `prompts/Work/ship.md` → exactly one `.chain`, `steps.count == 2`, `group == "Work"`, no `.prompt` with that id.
  - Behavioural `storePromptsExcludeChains`: `LibraryStore(...)` → `store.prompts` has no item with the chain id; `store.items` has it with `kind == .chain`.
  - Unit `promptMutationsIgnoreChainFiles`: `updatePrompt(id: chainID, title: "x", content: nil)` throws `.promptNotFound`, and the file bytes are unchanged.
  - Unit `reconcileSyncDoesNotExportChains`: after `reconcileSync()`, nothing named `ship` exists under `exportSkillsURL`.
  - Unit `chainEntryCodableRoundTrip`: the encoded JSON has `"kind":"chain"` and decodes back equal.
  - Unit `chainKindFoldersUsePromptsTree`: `folderURL(for: .chain, path: "A") == promptsDirectoryURL/A`.
  - Unit `writeChainThenLoadRoundTrips`: `writeChain` → `load()` gives back an equal `Chain` (with group nil at root).
- [ ] **Step 2:** `swift test --filter ChainRepositoryTests` → FAIL.
- [ ] **Step 3:** implement. `swift build` must compile all three targets. Fix each exhaustive-switch error with the minimal arm listed above.
- [ ] **Step 4:** full suite → 196 passed. `swift build` → `Build complete!`.
- [ ] **Step 5:** manual check: copy the test's raw chain file into a temp data dir, then run `swift run promptboard list --type chain --data-dir <dir>`. Expect 1 line with `chain`. `list --type prompt` must not show it.
- [ ] **Step 6:** commit `feat(kit): load chain files as .chain entries, never as prompts`.

## Task 3 (PR 3) — Kit: chain CRUD in repository + store

**Prerequisite:** PR 2 (`readChain`, `writeChain`, `.chain`).

**Files:**
- Create: `Sources/PromptBoardKit/LibraryRepository+Chains.swift`
- Modify: `LibraryRepository.swift`: add `case chainNotFound(UUID)` to `LibraryRepositoryError`, and widen `promptFileURLs`, `existingPromptSlugs`, `readChain` from `private` to internal
- Modify: `LibraryRepository+Folders.swift`: `relocatePromptFile` is reused by `moveChain` (no change expected)
- Modify: `LibraryStore.swift`: `chains`, `addChain`, `updateChain`; route `delete(id:)` and `moveItem(id:toFolder:)` as prompt → chain → skill
- Modify: `Sources/PromptBoardCLI/Support.swift:56,73` (message `chain not found: <id>`, exit code 2)
- Modify: `Tests/PromptBoardKitTests/ChainRepositoryTests.swift`

**Interfaces:**
```swift
// LibraryRepository, each self-locking like the prompt CRUD
@discardableResult public func addChain(title: String, steps: [Chain.Step], group: String? = nil) throws -> Chain
@discardableResult public func updateChain(id: UUID, title: String, steps: [Chain.Step]) throws -> Chain
@discardableResult public func deleteChain(id: UUID) throws -> Chain
public func moveChain(id: UUID, toFolder folder: String?) throws
func findChainFile(id: UUID) throws -> (url: URL, chain: Chain)?

// LibraryStore
public var chains: [Chain] { get }
@discardableResult public func addChain(title: String, steps: [Chain.Step], group: String? = nil) -> Chain?
public func updateChain(id: UUID, title: String, steps: [Chain.Step])
```
The slug is unique against `existingPromptSlugs()`, because chains share the prompts tree and the slash-alias namespace.

- [ ] **Step 1: failing tests**
  - Unit `addChainWritesKindChainFile`: the file contains `kind: chain` and `- @`, and `load()` returns equal steps.
  - Unit `addChainSlugAvoidsPromptCollision`: with prompt "Review" present, chain "Review" is written to `review-2.md`.
  - Unit `updateChainRewritesStepsAndBumpsUpdatedAt`: steps are replaced, `updatedAt` is later, `createdAt` is unchanged.
  - Unit `deleteChainKeepsLinkedPrompt`: the chain file is gone and the linked prompt file still exists.
  - Unit `moveChainRelocatesIntoFolder`: after `moveChain(id:toFolder:"Work")`, `load()` shows `group == "Work"`.
  - Unit `unknownChainIDThrowsChainNotFound`: `updateChain`, `deleteChain` and `moveChain` each throw `.chainNotFound`.
  - Behavioural `storeDeleteRoutesToChain`: `store.delete(id: chainID)` removes it from `store.chains`.
  - Behavioural `storeMoveItemRoutesToChain`: `store.moveItem(id: chainID, toFolder: "Work") == true`.
- [ ] **Step 2:** run → FAIL. **Step 3:** implement. **Step 4:** full suite → 204 passed; `swift build` OK.
- [ ] **Step 5:** commit `feat(kit): chain create, update, delete and move`.

## Task 4 (PR 4) — Kit: `ChainProgress` state file

**Prerequisite:** PR 3 (`LibraryStore.chains` for prune).

**Files:**
- Create: `Sources/PromptBoardKit/ChainProgress.swift`
- Modify: `LibraryRepository.swift` (`public var chainStateURL: URL { directoryURL.appendingPathComponent("chain-state.json") }`)
- Modify: `LibraryStore.swift` (`public let chainProgress: ChainProgress`, set in `init`; `loadInitial` calls `prune(keeping: Set(chains.map(\.id)))`)
- Create: `Tests/PromptBoardKitTests/ChainProgressTests.swift`

**Interfaces:**
```swift
public struct ChainProgress: Sendable {
    public let fileURL: URL
    public init(fileURL: URL)
    public func index(for chainID: UUID, stepCount: Int) -> Int   // stored value clamped to 0...stepCount; 0 if absent or the file is corrupt
    public func setIndex(_ index: Int, for chainID: UUID) throws  // atomic write, sorted keys, shape {"<uuid>": Int}
    public func prune(keeping chainIDs: Set<UUID>) throws         // no-op (creates nothing) when the file is absent
}
```
Leave a code comment: `shortcut: no flock, only the app writes this file; add the library lock if the CLI ever steps chains`.

- [ ] **Step 1: failing tests (Unit unless noted)**
  - `missingFileReadsZero`
  - `setThenReadRoundTrips`: `setIndex(2)` → `index(stepCount: 5) == 2`
  - `indexClampsWhenChainShrinks`: `setIndex(5)` → `index(stepCount: 2) == 2`
  - `corruptFileReadsZeroAndSetRecovers`: write `"{oops"` → reads 0; `setIndex(1)` → reads 1
  - `pruneDropsUnknownIDs`: two ids set, prune keeping one → the other reads 0, and the JSON has 1 key
  - `pruneWithoutFileCreatesNothing`: the file still does not exist
  - `stateFileIsOutsideLibraryDirectory`: `chainStateURL.path` does not start with `libraryURL.path`
  - Behavioural `storePrunesDeletedChainOnLaunch`: set an index for a random id, create a new `LibraryStore` on that dir → the JSON lacks that id
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** full suite → 212 passed.
- [ ] **Step 5:** commit `feat(kit): chain progress state file`.

## Task 5 (PR 5) — Kit: `ChainStepList` resolution + navigation

**Prerequisite:** PR 1 only. It can run in parallel with PRs 2–4. Its anti-goal test uses `addChain` and `ChainProgress`, so if it lands before PR 4, add that test in PR 4 instead.

**Files:**
- Create: `Sources/PromptBoardKit/ChainStepList.swift`
- Create: `Tests/PromptBoardKitTests/ChainStepListTests.swift`

**Interfaces:**
```swift
public struct ChainStepList: Equatable, Sendable {
    public enum Row: Equatable, Sendable { case ready(title: String, text: String), missing }
    public enum Activation: Equatable, Sendable { case paste(text: String, nextIndex: Int), restart, nothing }
    public let chain: Chain
    public let rows: [Row]                       // linked → prompt title + current content; custom → first line + text
    public private(set) var selectedIndex: Int?  // nil == done or empty
    public init(chain: Chain, prompts: [Prompt], progressIndex: Int)  // selects the first .ready at or after progressIndex
    public var isEmpty: Bool                     // no .ready rows (0 steps or all missing)
    public var isDone: Bool                      // !isEmpty && selectedIndex == nil
    public mutating func moveDown()              // next .ready; no-op at the end or when done
    public mutating func moveUp()                // previous .ready; from done, selects the last .ready
    public func activate() -> Activation         // selected N → .paste(rows[N] text, N + 1); done → .restart; empty → .nothing
}
```

- [ ] **Step 1: failing tests (Unit unless noted)**
  - `freshChainSelectsFirstStep`: progress 0 → `selectedIndex == 0`
  - `progressIndexSelectsThatStep`: progress 2 of 3 → `selectedIndex == 2`
  - `missingLinkedStepIsSkipped`: `[.linked(deleted), .custom("b")]` → `rows[0] == .missing`, `selectedIndex == 1`
  - `linkedStepUsesCurrentPromptContent`: the prompt's content is `"v2"` → `rows[0] == .ready(title: p.title, text: "v2")`
  - `activatePastesAndAdvances`: selected 1 → `.paste(text: <row 1>, nextIndex: 2)`
  - `arrowPickJumpsProgress`: progress 0, `moveDown()` twice → `activate() == .paste(_, nextIndex: 3)`
  - `moveSkipsMissingRows`: `[.custom, .linked(deleted), .custom]`, `moveDown()` from 0 → 2
  - `pastLastStepIsDoneAndRestarts`: progress == count → `isDone`, `activate() == .restart`
  - `missingTrailingStepsCountAsDone`: `[.custom, .linked(deleted)]`, progress 1 → `isDone`
  - `emptyChainCannotActivate`: 0 steps, and also all missing → `isEmpty`, `activate() == .nothing`
  - `moveUpFromDoneSelectsLastReadyStep`
  - Behavioural `fullRunLeavesLibraryFilesByteIdentical` (the spec's anti-goal check): add 2 prompts plus a 3-step chain, snapshot `Data` of every file under `libraryURL`, then loop `ChainStepList` → `activate` → `ChainProgress.setIndex` until done, then snapshot again → equal, and only `chain-state.json` differs in the data dir.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** full suite → +12 passed.
- [ ] **Step 5:** commit `feat(kit): chain step list resolution and navigation`.

## Task 6 (PR 6) — Kit: mixed ⌥/ ranking

**Prerequisite:** PR 2 (`.chain` case).

**Files:**
- Modify: `Sources/PromptBoardKit/PromptFilter.swift:40-62`
- Modify: `Tests/PromptBoardKitTests/PromptFilterTests.swift`

**Interfaces:**
```swift
public static func quickInsertResults(_ entries: [LibraryEntry], query: String) -> [LibraryEntry]
// Keeps .prompt and .chain only. Same tiers: exact alias, alias prefix, title, content.
// A chain's content is its custom step texts joined by "\n". Stable within a tier.
```
The existing `[Prompt]` overload stays as a one-line delegate (`.prompt` wrap → new overload → unwrap), so the current caller and tests stay green. PR 7 deletes it.

- [ ] **Step 1: failing tests (Unit)**
  - `mixedResultsDropSkills`: input prompt + skill + chain, empty query → `[prompt, chain]` in input order
  - `chainRanksByAliasLikePrompts`: query `/ship` → the chain titled "Ship" comes before a prompt whose content says "ship"
  - `chainMatchesCustomStepText`: query `"stop."` finds a chain whose custom step contains it
  - `chainDoesNotMatchLinkedPromptContent`: query = text only in the linked prompt → only that prompt is returned
  - `stableWithinTierAcrossKinds`: two title matches keep their input order
- [ ] **Step 2:** FAIL. **Step 3:** implement (extract the tier function once; both overloads use it). **Step 4:** full suite green, existing quick-insert tests unchanged.
- [ ] **Step 5:** commit `feat(kit): rank chains alongside prompts for quick insert`.

## Task 7 (PR 7) — ⌥/ popup: chain rows, step list, paste-and-advance (flagged)

**Prerequisite:** PRs 4, 5, 6.

**Files:**
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertModel.swift`
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertView.swift:85-125`
- Modify: `Sources/PromptBoardApp/Overlay/QuickInsertController.swift:161-200,272-289`
- Modify: `Sources/PromptBoardApp/DebugHooks.swift` (`handleQuickInsert` log adds kind; new `chainPick` hook)
- Modify: `Sources/PromptBoardKit/PromptFilter.swift` + `PromptFilterTests.swift` (delete the `[Prompt]` overload; move its tests onto `[LibraryEntry]` input)

**Interfaces:**
```swift
// QuickInsertModel
var results: [LibraryEntry]            // quickInsertResults(prompts + (Constants.chainsEnabled ? chains : [])), capped at 8
var selected: LibraryEntry?
private(set) var stepList: ChainStepList?   // non-nil == step-list mode
func moveDown(); func moveUp()              // route to stepList when it is open
func closeStepList()                        // Esc in step-list mode
func activate() -> String?                  // text to paste, or nil
// prompt → content. Chain row → opens stepList, returns nil. Empty chain → nil.
// Step list: .paste → chainProgress.setIndex(next) then return text; .restart → setIndex(0), rebuild, nil.

// QuickInsertController
private func insert(_ text: String)         // was insert(_ prompt: Prompt)
// Return: if let text = model.activate() { insert(text) }
// Escape: model.stepList != nil ? model.closeStepList() : hide()
func debugInsertFirst(query: String)        // same name; uses activate(), opening a chain if needed; logs kind and next index
func debugPickStep(query: String, step: Int)
```
View: a chain row uses the icon `list.number`, the subtitle `"N steps"`, and greys out as `"no steps"` when `isEmpty`. The step list shows the chain title, numbered rows, the selected row highlighted with `accent`, missing rows grey with `missing`, and a footer `done · ⏎ restarts` when `isDone`. Tapping a row selects it and activates it.

Debug hook `com.arya.PromptBoard.debug.chainPick`, object `"<query>|<step>"`. It calls `debugPickStep` and logs `PromptBoardDebug chainPick chain=<title> pasted=<first 40 chars> next=<n>`.

- [ ] **Step 1:** migrate `PromptFilterTests` off the `[Prompt]` overload, delete the overload → `swift test` green (no count change).
- [ ] **Step 2:** implement the model, view and controller. `swift build` → `Build complete!`.
- [ ] **Step 3 (Behavioural, debug):** `defaults write com.arya.PromptBoard chainsEnabled -bool true`, then `make run`. Create a 3-step chain "Ship" (step 2 linked) with `swift run promptboard` plus a hand-made file. Focus TextEdit. Then:
  - post `insertFirstResult` with `"ship"` three times → the log shows `next=1`, `next=2`, `next=3`, and TextEdit holds steps 1, 2, 3 in order
  - edit the linked prompt's content with `promptboard update`, reset `chain-state.json` to `{}`, post twice → the second paste is the new content
  - post `chainPick` with `"ship|2"` → `next=3`. Post again → the log shows `done`. Post once more → restart, then `next=1`
- [ ] **Step 4:** `swift test` green. With the flag off, `quickInsert` logs only prompts.
- [ ] **Step 5:** commit `feat(app): run chains from quick insert behind chainsEnabled`.

## Task 8 (PR 8) — Board: chain editor sheet (unwired)

**Prerequisite:** PR 3 (`store.addChain`, `updateChain`, `delete`).

**Files:**
- Create: `Sources/PromptBoardApp/Overlay/ChainEditorView.swift`
- Modify: `Sources/PromptBoardApp/AppState.swift` (mode, begin/save, `handleEscape` and `handleBackgroundClick` close it before `skillEditorMode`)
- Modify: `Sources/PromptBoardApp/Overlay/OverlayRootView.swift` (layer next to `skillEditorLayer`, same dim-and-tap-to-close pattern)
- Modify: `Sources/PromptBoardApp/DebugHooks.swift` (`newChain` hook)

**Interfaces:**
```swift
// AppState
enum ChainEditorMode: Equatable { case create, edit(Chain) }
var chainEditorMode: ChainEditorMode?
func beginCreatingChain()
func beginEditingChain(_ chain: Chain)
func saveChain(title: String, steps: [Chain.Step])   // create → store.addChain; edit → store.updateChain; then nil

// ChainEditorView(mode: AppState.ChainEditorMode, appState: AppState)
// State: title, steps: [Chain.Step]. Each row: number, linked → prompt title (or "missing"), custom → TextEditor bound by index,
// ↑ / ↓ buttons (disabled at the ends), remove button. Footer: "Add prompt" Menu over store.prompts, "Add custom", Delete (edit only), Cancel, Save.
// Save is disabled while the title is blank or any custom step is whitespace-only.
```
Nothing in the UI sets `chainEditorMode` yet. Only the debug hook does.

Debug hook `com.arya.PromptBoard.debug.newChain`, object `"<title>"`. It calls `beginCreatingChain()`, then `saveChain(title:, steps: [first prompt linked, .custom("debug step")])`, and logs `PromptBoardDebug newChain -> <id> steps=2`.

- [ ] **Step 1:** implement. `swift build` OK.
- [ ] **Step 2 (Behavioural, debug):** post `newChain` with `"Debug Chain"` → the log line appears, and `swift run promptboard list --type chain` lists it. Open the editor with the flag on, check it by eye (screenshot at 0.5 scale), then move a step up and save → `promptboard get <id>` shows the new order.
- [ ] **Step 3 (Behavioural):** delete the linked prompt with `promptboard delete` → the editor row shows `missing`.
- [ ] **Step 4:** commit `feat(app): chain editor sheet (unwired)`.

## Task 9 (PR 9) — Wire up: remove flag, New chain menu, card + detail, README

**Prerequisite:** PRs 7, 8.

**Files:**
- Modify: `Constants.swift` (delete `chainsEnabled`), `QuickInsertModel.swift` (always include chains), `AppState.swift:61` (stop filtering chains)
- Modify: `OverlayRootView.swift:88` (`Button("New chain") { appState.beginCreatingChain() }` in `newMenu`)
- Modify: `PromptCardView.swift` (chain: icon `list.number`, edit → `beginEditingChain`, delete help `Delete chain`, no convert action)
- Modify: `ItemDetailView.swift` (chain body: numbered step titles, `missing` where needed)
- Modify: `README.md` (a Chains section: file format, ⌥/ flow, state file path)

- [ ] **Step 1:** implement. `grep -rn chainsEnabled Sources` → no hits. `swift build` OK, and `swift test` green.
- [ ] **Step 2 (Behavioural re-run):** repeat Task 7 Step 3 without the defaults key. Then `defaults delete com.arya.PromptBoard chainsEnabled`.
- [ ] **Step 3 (Smoke):** in the real app, use ⌥Space → + → New chain to build "Ship" (spec prompt, plan prompt, one custom "review" step). In a real AI chat, press ⌥/ → "ship" → Enter → Enter once per turn for all 3 steps, then "done", then Enter to restart. Check that `find ~/Library/Application\ Support/PromptBoard/Library -name '*.md' -exec shasum {} + | shasum` gives the same value before and after the run.
- [ ] **Step 4:** commit `feat(app): wire up prompt chains`.

---

## Self-review

- Spec coverage: decisions 1–2 → PRs 1–3. Decision 3 → PRs 5, 7. Decision 4 → PRs 6, 7. Decision 5 → PR 8. Decisions 6 and anti-goal → PRs 4, 5. Decision 7 → PR 5. Decision 8 → PRs 5, 7. Calls 1–8 → PRs 2 (1, 4, 8), 4 (3), 1 (5), 5 (2, 6), 7 (7). Testing section → PR 5 anti-goal test, PR 7 debug checks, PR 9 smoke.
- Every PR compiles alone. PR 2 adds the case together with every exhaustive switch arm. PR 6 keeps the old overload until PR 7 removes its only caller.
- Until PR 9, users cannot create a chain in the UI, and chains are hidden while the flag is off.
- Open: test counts after PR 4 depend on whether PR 5 merged first. Check against the real `swift test` total, never a typed number.
