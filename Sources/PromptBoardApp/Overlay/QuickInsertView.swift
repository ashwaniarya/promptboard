import SwiftUI
import PromptBoardKit

// Compact caret popup: a slash search field over a keyboard-navigable list of
// prompts and chains, or an open chain's steps. Typing goes to the field; ↑↓/⏎/esc are
// handled by the controller's key monitor (SwiftUI focus is unreliable in a non-activating panel). Tap activates.
struct QuickInsertView: View {
    @Bindable var model: QuickInsertModel
    let onActivate: () -> Void

    static let searchPlaceholder = "insert a prompt…"
    static let chainTitlePlaceholder = "Chain title"
    static let stepSearchPlaceholder = "add a step: search prompts or type text…"
    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            if let draft = model.chainDraft {
                chainEditor(draft)
            } else {
                searchField
                tabStrip
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                if model.tab == .clipboard { clipboardList } else { results }
            }
        }
        .frame(width: 440)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.13)))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Text("/").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
            TextField(Self.searchPlaceholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            Spacer(minLength: 6)
            Text("\(model.visibleCount)")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            tabButton("Prompts", tab: .prompts)
            tabButton("Clipboard", tab: .clipboard)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private func tabButton(_ title: String, tab: QuickInsertModel.Tab) -> some View {
        let active = model.tab == tab
        return Text(title)
            .font(.system(size: 11, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Color.white : Color.white.opacity(0.5))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(active ? accent.opacity(0.25) : .clear))
            .contentShape(Capsule())
            .onTapGesture { model.tab = tab }
    }

    @ViewBuilder
    private var clipboardList: some View {
        let clips = model.clipboardResults
        if clips.isEmpty {
            Text(model.query.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(clips.enumerated()), id: \.offset) { index, clip in
                    clipRow(clip, index: index)
                }
            }
            .padding(6)
        }
    }

    private func clipRow(_ clip: String, index: Int) -> some View {
        let selected = index == model.selectedIndex
        return HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13)).frame(width: 16)
                .foregroundStyle(selected ? accent : Color.white.opacity(0.55))
            Text(clip.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 6)
        }
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.82))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.20) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedIndex = index
            onActivate()
        }
    }

    @ViewBuilder
    private var results: some View {
        if let stepList = model.stepList {
            stepListView(stepList)
        } else {
            VStack(spacing: 2) {
                if model.results.isEmpty {
                    Text(model.query.isEmpty ? "No prompts to insert" : "No matches")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 14)
                }
                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, entry in
                    row(entry, index: index)
                }
                newChainRow
                Group {
                    if case .chain(let chain)? = model.selected, !model.progressView(for: chain).isEmpty {
                        Text("⏎ paste next · → open steps · ⌘E edit chain · ⌘N new chain")
                    } else {
                        Text("⇥ switch tab · ⌘E edit chain · ⌘N new chain")
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
            }
            .padding(6)
        }
    }

    private func row(_ entry: LibraryEntry, index: Int) -> some View {
        let selected = index == model.selectedIndex
        var progress: ChainProgressView?
        if case .chain(let chain) = entry { progress = model.progressView(for: chain) }
        let emptyChain = progress?.isEmpty ?? false
        return HStack(spacing: 10) {
            Image(systemName: entry.kind == .chain ? "list.number" : "doc.text")
                .font(.system(size: 13)).frame(width: 16)
                .foregroundStyle(selected ? accent : Color.white.opacity(0.55))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if case .chain(let chain) = entry {
                        Text("chain · \(chain.steps.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(accent.opacity(0.18)))
                    }
                }
                if let progress, !progress.isEmpty {
                    progressBar(progress).padding(.vertical, 3)
                    if selected {
                        Text(progress.isDone ? "All \(progress.stepCount) done · ⏎ restarts" : "Next: \(progress.nextPreview ?? "")")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text(emptyChain ? "no steps" : entry.previewText.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text("/\(Slug.make(from: entry.title))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(selected ? accent : Color.white.opacity(0.4)).lineLimit(1)
        }
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.82))
        .opacity(emptyChain ? 0.45 : 1)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.20) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedIndex = index
            onActivate()
        }
    }

    private var newChainRow: some View {
        let selected = model.isNewChainRowSelected
        return HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 13)).frame(width: 16)
                .foregroundStyle(selected ? accent : Color.white.opacity(0.55))
            Text("New chain").font(.system(size: 13, weight: .medium))
            Spacer(minLength: 6)
            Text("⌘N").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.white.opacity(0.4))
        }
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.65))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.20) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedIndex = model.results.count
            onActivate()
        }
    }

    private func chainEditor(_ draft: ChainDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.number").foregroundStyle(accent)
                TextField(Self.chainTitlePlaceholder, text: Binding(
                    get: { model.chainDraft?.title ?? "" },
                    set: { title in model.updateChainDraft { $0.title = title } }
                ))
                .textFieldStyle(.plain).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 6)
                Text(draft.chainID == nil ? "new chain" : "edit chain")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            VStack(spacing: 2) {
                if draft.steps.isEmpty {
                    Text("No steps yet")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                }
                ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                    draftStepRow(step, index: index, selected: index == draft.selectedStep)
                }
            }
            .padding(6)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                TextField(Self.stepSearchPlaceholder, text: Binding(
                    get: { model.chainDraft?.query ?? "" },
                    set: { query in model.updateChainDraft { $0.query = query } }
                ))
                .textFieldStyle(.plain).font(.system(size: 13))
            }
            .padding(.horizontal, 15).padding(.vertical, 10)
            VStack(spacing: 2) {
                ForEach(Array(model.pickerRows.enumerated()), id: \.offset) { index, row in
                    pickerRow(row, index: index, selected: index == draft.pickerIndex)
                }
            }
            .padding(.horizontal, 6).padding(.bottom, 4)
            if let error = model.chainSaveError {
                Text(error).font(.system(size: 11)).foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 4)
            }
            Text("⏎ add · ⌘⏎ custom · ⌥↑↓ move · ⌘⌫ remove · ⌘S save · esc cancel")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        }
    }

    private func draftStepRow(_ step: Chain.Step, index: Int, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 9, design: .monospaced))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(lineWidth: 1))
                .foregroundStyle(selected ? accent : Color.white.opacity(0.45))
            switch step {
            case .linked(let promptID):
                Image(systemName: "link").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55))
                if let title = model.promptTitle(for: promptID) {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                } else {
                    Text("missing").font(.system(size: 13)).italic().foregroundStyle(Color.white.opacity(0.35))
                }
            case .custom(let text):
                Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55))
                TextField("custom step", text: Binding(
                    get: { text },
                    set: { newText in model.updateChainDraft { $0.setCustomText(newText, at: index) } }
                ), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4)
            }
            Spacer(minLength: 6)
        }
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.82))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.20) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { model.updateChainDraft { $0.selectStep(index) } }
    }

    private func pickerRow(_ row: ChainDraft.PickerRow, index: Int, selected: Bool) -> some View {
        HStack(spacing: 10) {
            switch row {
            case .prompt(let prompt):
                Image(systemName: "doc.text").font(.system(size: 12)).frame(width: 16)
                    .foregroundStyle(selected ? accent : Color.white.opacity(0.55))
                Text(prompt.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            case .custom(let text):
                Image(systemName: "pencil").font(.system(size: 12)).frame(width: 16)
                    .foregroundStyle(selected ? accent : Color.white.opacity(0.55))
                Text("Use \"\(text)\" as custom step").font(.system(size: 12)).lineLimit(1)
            }
            Spacer(minLength: 6)
        }
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.75))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? accent.opacity(0.16) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            model.movePicker(by: index - (model.chainDraft?.pickerIndex ?? 0))
            model.addPickedStep()
        }
    }

    private func progressBar(_ progress: ChainProgressView) -> some View {
        let doneColor = Color.green.opacity(0.85)
        let upcomingColor = Color.white.opacity(0.13)
        return Group {
            if progress.usesContinuousBar {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5).fill(upcomingColor)
                        RoundedRectangle(cornerRadius: 1.5).fill(doneColor)
                            .frame(width: geometry.size.width * CGFloat(progress.completedCount) / CGFloat(progress.stepCount))
                    }
                }
                .frame(height: 3)
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(progress.segments.enumerated()), id: \.offset) { _, segment in
                        switch segment {
                        case .done: RoundedRectangle(cornerRadius: 1.5).fill(doneColor).frame(height: 3)
                        case .current: RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(height: 3)
                        case .upcoming: RoundedRectangle(cornerRadius: 1.5).fill(upcomingColor).frame(height: 3)
                        case .missing: Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                        }
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func stepListView(_ stepList: ChainStepList) -> some View {
        let progress = ChainProgressView(stepList: stepList)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "list.number").foregroundStyle(accent)
                Text(stepList.chain.title).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 6)
                Text(progress.isDone ? "done" : "step \(progress.completedCount + 1) of \(progress.stepCount)")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            ForEach(Array(stepList.rows.enumerated()), id: \.offset) { index, row in
                stepRow(
                    row, index: index, selected: index == stepList.selectedIndex,
                    isDone: progress.segments[index] == .done, tag: progress.rowTags[index]
                )
            }
            Text("⏎ paste and advance · ↑↓ pick · ⌘R restart · esc back")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        }
        .padding(6)
    }

    private func stepRow(_ row: ChainStepList.Row, index: Int, selected: Bool, isDone: Bool, tag: ChainProgressView.Tag) -> some View {
        let title: String
        let isMissing: Bool
        switch row {
        case .ready(let readyTitle, _): title = readyTitle; isMissing = false
        case .missing: title = "missing"; isMissing = true
        }
        let tagText: String
        switch tag {
        case .now: tagText = "now"
        case .linked: tagText = "linked"
        case .custom: tagText = "custom"
        case .missingSkipped: tagText = "missing, skipped"
        }
        return HStack(spacing: 10) {
            Group {
                if isDone {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 9, design: .monospaced))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(lineWidth: 1))
                }
            }
            .frame(width: 16)
            .foregroundStyle(selected ? accent : Color.white.opacity(0.45))
            Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                .italic(isMissing)
            Spacer(minLength: 6)
            Text(tagText)
                .font(.system(size: 10))
                .foregroundStyle(tag == .now ? accent : Color.white.opacity(0.4))
        }
        .foregroundStyle(isMissing ? Color.white.opacity(0.35) : selected ? Color.white : Color.white.opacity(0.82))
        .opacity(isDone ? 0.5 : 1)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.20) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMissing else { return }
            model.selectStep(index)
            onActivate()
        }
    }
}
