import AppKit
import SwiftUI

/// Floating recording pill: logo, waveform/elapsed, Stop button, ⋯ menu.
struct RecordingHUDView: View {
    let onStop: () -> Void
    let onOpenWindow: () -> Void
    let onOpenNotes: () -> Void
    let onOpenConfig: () -> Void
    let onOpenLog: () -> Void
    let onQuit: () -> Void

    @State private var state = RecordingState.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            brandLogo
            divider
            phaseContent
                .animation(.smooth(duration: 0.3), value: state.phase)
            menu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Theme.bg.opacity(0.92)))
        .overlay(Capsule(style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .fixedSize()
        // Rest faded so it disappears into a shared screen; brighten on hover.
        .opacity(hovering ? 1 : 0.32)
        .animation(.easeInOut(duration: 0.25), value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var phaseContent: some View {
        if state.phase == .transcribing || state.phase == .summarizing {
            processingContent
        } else {
            recordingContent
        }
    }

    private var brandLogo: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable().interpolation(.high)
            .frame(width: 16, height: 16)
            .accessibilityLabel("Earwig")
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 14)
    }

    private var recordingContent: some View {
        HStack(spacing: 7) {
            LiveWaveform(active: state.isRecording)
            Text(state.elapsedLabel)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            stopButton
        }
        .transition(.opacity)
    }

    private var processingContent: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.accent)
            Text(state.phase == .summarizing ? "Summarising…" : "Transcribing…")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .transition(.opacity)
    }

    private var stopButton: some View {
        Button("Stop recording", systemImage: "stop.fill", action: onStop)
            .labelStyle(.iconOnly)
            .font(.caption.weight(.bold))
            .foregroundStyle(.red)
            .buttonStyle(.plain)
            .clickableCursor()
    }

    private var menu: some View {
        Menu {
            Button("Open Earwig", action: onOpenWindow)
            Button("Open Notes Folder", action: onOpenNotes)
            Button("Open Config File", action: onOpenConfig)
            Button("Open Log", action: onOpenLog)
            Divider()
            Button("Quit Earwig", action: onQuit)
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Animated waveform bars during recording; static dot when inactive or Reduce Motion is on.
private struct LiveWaveform: View {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 4
    private let barWidth: CGFloat = 2.5
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 14

    var body: some View {
        Group {
            if reduceMotion || !active {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 7, height: 7)
                    .opacity(active ? 0.9 : 0.4)
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    HStack(alignment: .center, spacing: 2.5) {
                        ForEach(0 ..< barCount, id: \.self) { index in
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: barWidth, height: height(index, t))
                        }
                    }
                }
            }
        }
        .frame(width: 22, height: maxHeight)
        .accessibilityHidden(true)
    }

    private func height(_ index: Int, _ time: Double) -> CGFloat {
        // Offset each bar's phase so the bars ripple rather than move in unison.
        let phase = Double(index) * 0.7
        let unit = (sin(time * 4.2 + phase) + 1) / 2   // 0…1
        return minHeight + (maxHeight - minHeight) * unit
    }
}
