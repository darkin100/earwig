import SwiftUI

/// Floating search panel shown by command-K. Queries the in-memory `SearchService` and
/// lets the user jump to any meeting. Selecting a result posts `.earwigOpenMeeting`
/// and closes the panel.
///
/// Also supports Ask mode: typing a question and pressing command-Return (or clicking the
/// "Ask" row) sends the query through the configured summary engine and shows the answer
/// with source chips that open the cited meeting.
struct SpotlightView: View {
    let search: SearchService
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var hits: [SearchHit] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    // Ask mode state
    @State private var asking = false
    @State private var askResult: AskResult?
    @State private var askError: String?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Dimmed backdrop separates the white card from the (also white) window behind it,
            // and dismisses the spotlight when tapped outside the card.
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            card
                .padding(.top, 140)
        }
        .preferredColorScheme(.light)
        .onExitCommand { onClose() }
        .onAppear { fieldFocused = true }
        // Arrow keys move the selection through results even while the search field holds focus.
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        // Command-Return triggers Ask mode.
        .onKeyPress(.return, phases: .down) { event in
            guard event.modifiers.contains(.command), !trimmedQuery.isEmpty else {
                return .ignored
            }
            runAsk()
            return .handled
        }
        .onChange(of: query) {
            selectedIndex = 0
            askResult = nil
            askError = nil
            let current = trimmedQuery
            if current.isEmpty {
                hits = []
                searchTask?.cancel()
                searchTask = nil
                return
            }
            searchTask?.cancel()
            let docs = search.docs
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000) // 150 ms debounce
                guard !Task.isCancelled else { return }
                let ranked = SearchService.rank(query: current, in: docs)
                hits = Array(ranked.prefix(8))
                selectedIndex = 0
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            searchField
            if !trimmedQuery.isEmpty {
                Hairline()
                askRow
            }
            if !hits.isEmpty {
                Hairline()
                resultsList
            }
            if asking || askResult != nil || askError != nil {
                Hairline()
                askPanel
            }
        }
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Color.black.opacity(0.28), radius: 40, y: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    /// Move the highlighted result by `delta`, clamped to the result range.
    private func move(_ delta: Int) {
        guard !hits.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), hits.count - 1)
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            TextField("Search your meetings...", text: $query)
                .textFieldStyle(.plain)
                .font(.bodyText)
                .foregroundStyle(Theme.textPrimary)
                .focused($fieldFocused)
                .onSubmit {
                    if hits.indices.contains(selectedIndex) {
                        open(hits[selectedIndex])
                    }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .clickableCursor()
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    /// The "Ask" affordance row shown below the search field when there is a non-empty query.
    private var askRow: some View {
        Button {
            runAsk()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text("Ask \"\(trimmedQuery)\"")
                    .font(.label)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("command + Return")
                    .font(.captionText)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask a question about your meetings")
        .clickableCursor()
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.xxs) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                        resultRow(hit, index: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
            }
            .frame(maxHeight: 440)
            .onChange(of: selectedIndex) {
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(selectedIndex, anchor: .center) }
            }
        }
    }

    private func resultRow(_ hit: SearchHit, index: Int) -> some View {
        let isSelected = index == selectedIndex
        return Button {
            open(hit)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text(hit.title)
                        .font(.label)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.sm)
                    Text(hit.date, style: .date)
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                }
                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.12) : Color.clear)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Theme.accent : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, Spacing.sm)
            }
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .onHover { hovering in
            if hovering { selectedIndex = index }
        }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    /// The answer panel shown when Ask has been run. Includes a spinner while thinking,
    /// the answer text plus source chips when done, or an error message on failure.
    @ViewBuilder
    private var askPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if asking {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking...")
                            .font(.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.lg)
                } else if let result = askResult {
                    Text(result.answer)
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top], Spacing.lg)

                    if !result.sources.isEmpty {
                        sourceChips(for: result.sources)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.bottom, Spacing.lg)
                    } else {
                        Spacer().frame(height: Spacing.md)
                    }
                } else if let error = askError {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Theme.danger)
                        Text(error)
                            .font(.captionText)
                            .foregroundStyle(Theme.danger)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.lg)
                }
            }
        }
        .frame(maxHeight: 360)
    }

    /// A wrapping row of badge-style buttons, one per source meeting.
    private func sourceChips(for meetingIDs: [String]) -> some View {
        let docsByID = Dictionary(uniqueKeysWithValues: search.docs.map { ($0.meetingId, $0) })
        return FlowLayout(spacing: Spacing.xs) {
            ForEach(meetingIDs, id: \.self) { meetingID in
                let label = docsByID[meetingID]?.title ?? meetingID
                Button {
                    openByID(meetingID)
                } label: {
                    Text(label)
                        .font(.captionText)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Capsule().fill(Theme.accent.opacity(0.10)))
                        .overlay(Capsule().stroke(Theme.accent.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open meeting: \(label)")
                .clickableCursor()
            }
        }
    }

    // MARK: - Actions

    private func open(_ hit: SearchHit) {
        NotificationCenter.default.post(
            name: .earwigOpenMeeting,
            object: nil,
            userInfo: ["id": hit.meetingId]
        )
        onClose()
    }

    private func openByID(_ meetingID: String) {
        NotificationCenter.default.post(
            name: .earwigOpenMeeting,
            object: nil,
            userInfo: ["id": meetingID]
        )
        onClose()
    }

    private func runAsk() {
        guard !trimmedQuery.isEmpty, !asking else { return }
        let question = trimmedQuery
        asking = true
        askError = nil
        askResult = nil

        let config = Config.load()
        let engine = SummaryEngineKind.from(config.summaryEngine)
        let docs = search.contextDocs(for: question,
                                      budgetChars: AskService.contextBudget(for: engine))

        Task {
            do {
                let result = try await AskService.ask(
                    question: question,
                    docs: docs,
                    engine: engine,
                    modelID: config.summaryModelID,
                    claudeModel: config.summaryClaudeModel
                )
                askResult = result
            } catch {
                askError = error.localizedDescription
            }
            asking = false
        }
    }
}

// MARK: - FlowLayout

/// A simple wrapping layout that flows children left-to-right, wrapping onto new rows.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.maxX
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
