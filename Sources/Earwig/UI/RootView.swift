import SwiftUI

/// The Meetings browser window: sidebar → date-grouped list → transcript detail.
struct RootView: View {
    @State private var store = MeetingsStore()
    @State private var identityStore = IdentityStore()
    @State private var settingsStore = SettingsStore()
    @State private var section: NavSection = .meetings
    @State private var selection: Meeting?

    // Search + feedback are presented as overlays inside the main (key) window rather than separate
    // panels, so their text fields reliably receive keyboard focus.
    @State private var searchService = SearchService()
    @State private var showSearch = false
    @State private var showFeedback = false
    // Pin the sidebar visible so macOS never collapses it into a floating slide-over panel.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $section)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detailArea
        }
        .navigationSplitViewStyle(.balanced)
        .background(Theme.bg)
        .preferredColorScheme(.light)
        .overlay { if showSearch { SpotlightView(search: searchService) { showSearch = false } } }
        .overlay { if showFeedback { FeedbackView { showFeedback = false } } }
        .overlay(alignment: .top) { ToastOverlay() }
        .frame(minWidth: 1280, minHeight: 860)
        .onReceive(NotificationCenter.default.publisher(for: .earwigOpenHelp)) { _ in section = .help }
        .onReceive(NotificationCenter.default.publisher(for: .earwigOpenAbout)) { _ in section = .about }
        .onReceive(NotificationCenter.default.publisher(for: .earwigOpenSearch)) { _ in
            // Open instantly; the field starts empty, so the index finishes loading in the
            // background well before the user types a query.
            showSearch = true
            Task { await searchService.reload(notesFolder: Config.load().notesFolderURL) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .earwigOpenFeedback)) { _ in
            showFeedback = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .earwigOpenMeeting)) { note in
            guard let meetingId = note.userInfo?["id"] as? String else { return }
            section = .meetings
            // Only navigate when the meeting is actually loaded; otherwise keep the current
            // selection and tell the user, rather than silently clearing it.
            if let match = store.meetings.first(where: { $0.id == meetingId }) {
                selection = match
            } else {
                ToastCenter.shared.warning("That meeting could not be opened")
            }
        }
    }

    // Only Meetings is a master/detail (list + transcript). People and Settings own the
    // whole area right of the sidebar, so switching to them no longer leaves a stale
    // meeting transcript stranded in a third column.
    @ViewBuilder
    private var detailArea: some View {
        switch section {
        case .meetings:
            HStack(spacing: 0) {
                MeetingsListView(store: store, selection: $selection)
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: 560)
                Rectangle().fill(Theme.hairline).frame(width: 1)
                MeetingDetailView(meeting: selection, store: store, onDelete: { selection = nil })
                    .frame(maxWidth: .infinity)
            }
        case .people:
            PeopleView(store: identityStore)
        case .settings:
            SettingsView(store: settingsStore)
        case .help:
            HelpView()
        case .about:
            AboutView()
        }
    }
}
