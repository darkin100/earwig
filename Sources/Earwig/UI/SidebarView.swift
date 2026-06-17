import SwiftUI

extension Notification.Name {
    static let earwigToggleRecording = Notification.Name("earwigToggleRecording")
    /// Posted after a meeting note is written so the browser list reloads.
    static let earwigMeetingsChanged = Notification.Name("earwigMeetingsChanged")
    /// Posted after a voiceprint is enrolled or forgotten so the People list reloads.
    static let earwigIdentitiesChanged = Notification.Name("earwigIdentitiesChanged")
    /// Posted after settings are saved so the app reloads its config without a restart.
    static let earwigConfigChanged = Notification.Name("earwigConfigChanged")
    /// Posted to re-open the first-run onboarding flow (from the menu or Settings).
    static let earwigRerunOnboarding = Notification.Name("earwigRerunOnboarding")
    /// Posted by the window toolbar to navigate to Help / About.
    static let earwigOpenHelp = Notification.Name("earwigOpenHelp")
    static let earwigOpenAbout = Notification.Name("earwigOpenAbout")
    /// Posted by the spotlight panel to open a specific meeting. `userInfo["id"]` is the
    /// meeting stem (e.g. "meeting-2026-06-16-0931").
    static let earwigOpenMeeting = Notification.Name("earwigOpenMeeting")
    /// Posted by the sidebar to open the feedback form.
    static let earwigOpenFeedback = Notification.Name("earwigOpenFeedback")
    /// Posted by the toolbar / menu (⌘K) to open the search spotlight.
    static let earwigOpenSearch = Notification.Name("earwigOpenSearch")
}

/// Top-level navigation sections in the sidebar.
enum NavSection: String, CaseIterable, Identifiable {
    case meetings
    case people
    case settings
    case help
    case about

    var id: String { rawValue }

    /// Main destinations shown at the top of the sidebar (Help/About are footer icon buttons).
    static let primary: [NavSection] = [.meetings, .people, .settings]

    var title: String {
        switch self {
        case .meetings: return "Meetings"
        case .people: return "People"
        case .settings: return "Settings"
        case .help: return "Help"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .meetings: return "waveform"
        case .people: return "person.2"
        case .settings: return "gearshape"
        case .help: return "questionmark.circle"
        case .about: return "info.circle"
        }
    }
}

/// Left column: brand, Record button, section navigation, and a live status
/// row pinned to the bottom (recovering the ambient status the menu bar showed).
struct SidebarView: View {
    @Binding var selection: NavSection

    @State private var recState = RecordingState.shared
    @State private var cpu = CPUMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            brand
            recordButton
            navList
            Spacer(minLength: 0)
            footer
        }
        .padding(Spacing.lg)
        .frame(minWidth: 240)
        .background(Theme.surface)
        .overlay(Rectangle().fill(Theme.hairline).frame(width: 1), alignment: .trailing)
        .onAppear { cpu.start() }
        .onDisappear { cpu.stop() }
    }

    private var brand: some View {
        BrandMark()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.xs)
    }

    private var recordButton: some View {
        let recording = recState.isRecording
        return Button {
            NotificationCenter.default.post(name: .earwigToggleRecording, object: nil)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: recording ? "stop.fill" : "record.circle.fill")
                Text(recording ? "Stop recording" : "Record")
                    .fontWeight(.semibold)
                Spacer()
            }
            .font(.label)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(recording
                          ? AnyShapeStyle(Theme.danger)
                          : AnyShapeStyle(Theme.primaryGradient)))
            .shadow(color: (recording ? Theme.danger : Theme.accent).opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .clickableCursor()
    }

    /// Width reserved for the leading glyph in both footer rows, so the feedback label and the
    /// status label start on the same vertical line.
    private let footerGlyphWidth: CGFloat = 22

    /// Footer block: the "Send feedback" affordance, then one compact status line.
    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            feedbackButton
            statusBar
        }
    }

    /// Compact CPU readout for the status line: a small cpu glyph + percentage, tinted by load.
    private var cpuChip: some View {
        let percent = Int((cpu.usage * 100).rounded())
        return HStack(spacing: Spacing.xxs) {
            Image(systemName: "cpu").font(.system(size: 11, weight: .medium))
            Text("\(percent)%").font(.captionText).monospacedDigit()
        }
        .foregroundStyle(cpuColor(cpu.usage))
        .animation(.easeOut(duration: 0.4), value: cpu.usage)
        .help("Total CPU usage across all cores (transcription runs on the Neural Engine, summaries in Ollama)")
    }

    private func cpuColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.5: return Theme.green
        case ..<0.8: return Theme.amber
        default: return Theme.danger
        }
    }

    /// A friendly prompt to send feedback (opens the form overlay).
    private var feedbackButton: some View {
        Button {
            NotificationCenter.default.post(name: .earwigOpenFeedback, object: nil)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 14))
                    .frame(width: footerGlyphWidth)
                Text("Send feedback")
                    .fontWeight(.medium)
                Spacer(minLength: 0)
            }
            .font(.label)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Theme.elevated.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
        .clickableCursor()
    }

    /// Pinned status row: animated waves while recording/transcribing/summarising, static bars
    /// at idle. The app version is shown when idle; live status otherwise.
    private var statusBar: some View {
        HStack(spacing: Spacing.sm) {
            SoundBars(color: statusColor, animated: recState.phase != .idle)
                .frame(width: footerGlyphWidth, alignment: .center)
                .help("Waiting for meetings")
            Text(statusLabel)
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: Spacing.sm)
            cpuChip
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.md)
        .overlay(Hairline().padding(.horizontal, -Spacing.lg), alignment: .top)
    }

    private var statusColor: Color {
        switch recState.phase {
        case .idle: return Theme.accent
        case .recording: return Theme.danger
        case .transcribing, .summarizing: return Theme.amber
        }
    }

    private var statusLabel: String {
        switch recState.phase {
        // When idle the animated waves already say "live and waiting", so the footer shows the
        // app version instead of repeating that.
        case .idle: return "Earwig \(AppInfo.version)"
        case .recording: return "Recording \(recState.elapsedLabel)"
        case .transcribing: return "Transcribing…"
        case .summarizing: return "Summarising…"
        }
    }

    private var navList: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(NavSection.primary) { section in
                navRow(section)
            }
        }
    }

    private func navRow(_ section: NavSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: section.symbol)
                    .frame(width: 18)
                Text(section.title)
                Spacer()
            }
            .font(.label).fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? Theme.elevated : Color.clear)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(isSelected ? Theme.accent : Color.clear)
                    .frame(width: 2.5)
                    .padding(.vertical, Spacing.xs)
            }
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
