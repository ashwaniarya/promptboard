# PromptBoard

A macOS prompt manager that lives in your menu bar. Press **⌥Space** anywhere and a full-screen overlay appears over a blurred desktop, showing your prompts as a Pinterest-style masonry grid.

- **Single-click** a card → copies the prompt to the clipboard (overlay stays open)
- **Double-click** a card → edit it
- **Two-finger scroll** → browse the grid
- **Type** → live-search prompts (search is focused on open)
- **⌘N / +** → new prompt · hover **✕** → delete
- **Esc** → clears search, then closes · **⌥Space** or click empty space → closes

Prompts are stored as human-readable JSON in `~/Library/Application Support/PromptBoard/prompts.json`.

## Build & run

```bash
swift build          # compile
swift test           # unit tests (store, filter, masonry)
swift run            # dev loop (menu bar icon appears; Ctrl-C to quit)
make app             # assemble + ad-hoc sign dist/PromptBoard.app
open dist/PromptBoard.app
```

Requires macOS 14+. No Xcode project — pure SwiftPM. For **Launch at Login**, run the bundled `dist/PromptBoard.app` (the toggle is disabled under `swift run`; move the app to `/Applications` for a stable login item).

⚠️ Don't run `swift run` and the bundled app at once — the second instance's hotkey registration fails (logged to console).

### Dev hooks (env vars)

- `PROMPTBOARD_SHOW_ON_LAUNCH=1` — open the overlay immediately at launch
- `PROMPTBOARD_DATA_DIR=/path` — use a different prompts.json directory (keeps your real library untouched)
- `PROMPTBOARD_DEBUG=1` — listen for distributed notifications used for scripted UI verification: `com.arya.PromptBoard.debug.toggle` (toggle overlay), `…debug.newPrompt` (open overlay + blank editor), `…debug.commandKey` (replay a ⌘-key equivalent; object = character, e.g. `"v"`), `…debug.dumpState` (log key window, first responder, and each text field's value/focus), `…debug.snapshot` (write a PNG of the overlay content; object = output path). Post one with:

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
12. Quit + relaunch → data persists. Hand-corrupt the JSON → app recovers with seeds and leaves a `.corrupt-*` backup.
13. Bundled app only: Launch at Login toggle flips the checkmark and appears in System Settings → General → Login Items.
