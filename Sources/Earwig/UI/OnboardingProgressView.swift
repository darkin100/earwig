import SwiftUI

/// The Models step body: downloads + warms the on-device models with a single progress bar
/// and a per-model breakdown (name + size + live status), so it's clear exactly what's being
/// downloaded and how much disk it uses. Retryable on failure; Finish is gated by
/// `state.modelsReady` in `OnboardingView`.
struct OnboardingProgressView: View {
    @Bindable var state: OnboardingState

    private struct Stage {
        let title: String
        let detail: String
        let sizeGB: Double
        let completeAt: Double   // bar value at which this stage is finished
    }

    private var stages: [Stage] {
        [
            Stage(title: "Speech", detail: "Whisper large-v3",
                  sizeGB: 0.6, completeAt: ModelProvisioner.whisperWeight),
            Stage(title: "Speakers", detail: "pyannote community-1 + WeSpeaker",
                  sizeGB: 0.1, completeAt: 1.0),
        ]
    }

    private var totalSizeGB: Double { stages.reduce(0) { $0 + $1.sizeGB } }

    var body: some View {
        GlossyCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Setting up on-device intelligence")
                    .font(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)

                Text("Earwig downloads two models so your first meeting transcribes instantly. Everything runs on your Mac — nothing is uploaded. (Summaries are set up next.)")
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.modelPhase {
        case .failed(let detail):
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Download failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.label).fontWeight(.semibold)
                    .foregroundStyle(Theme.amber)
                Text(detail)
                    .font(.captionText).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") { Task { await state.downloadModels() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
        default:
            VStack(alignment: .leading, spacing: Spacing.lg) {
                progressBar
                modelList
                Text("About \(formatted(totalSizeGB)) on your Mac · stored once, used offline")
                    .font(.captionText)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ProgressView(value: state.modelProgress).tint(Theme.accent)
            HStack {
                Text(state.modelsReady ? "Models ready" : "Downloading…")
                    .font(.captionText).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(state.modelProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.captionText).monospacedDigit().foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var modelList: some View {
        VStack(spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                if index > 0 { Hairline() }
                row(stage)
            }
        }
    }

    private func row(_ stage: Stage) -> some View {
        HStack(spacing: Spacing.md) {
            statusIcon(for: stage)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(stage.title)
                    .font(.label).fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Text(stage.detail)
                    .font(.captionText).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            Text(formatted(stage.sizeGB))
                .font(.captionText).monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, Spacing.md)
    }

    @ViewBuilder
    private func statusIcon(for stage: Stage) -> some View {
        switch status(for: stage) {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        case .active:
            ProgressView().controlSize(.small).tint(Theme.accent)
        case .pending:
            Image(systemName: "circle").foregroundStyle(Theme.textTertiary)
        }
    }

    private enum RowStatus { case done, active, pending }

    private func status(for stage: Stage) -> RowStatus {
        if state.modelsReady || state.modelProgress + 0.0001 >= stage.completeAt { return .done }
        // The active stage is the first not-yet-complete one.
        if let first = stages.first(where: { state.modelProgress + 0.0001 < $0.completeAt }),
           first.title == stage.title {
            return .active
        }
        return .pending
    }

    private func formatted(_ gb: Double) -> String {
        gb < 1 ? "~\(Int(gb * 1000)) MB" : "~\(String(format: "%.1f", gb)) GB"
    }
}
