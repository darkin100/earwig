import AppKit
import SwiftUI

/// First-run welcome flow: Welcome → Permissions → Models. Earwig is the star (logo +
/// name); ClearRoute is the secondary brand. Calls `onComplete` when the user finishes the
/// (mandatory) model download, so the host can persist the flag and open the main window.
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var state = OnboardingState.shared
    // Shared with the summary step so the Finish gate sees the same engine/model/install status.
    @State private var settings = SettingsStore()
    @State private var ollama = OllamaState()
    @State private var verifyingClaude = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(28)
            footer
        }
        .frame(width: 640, height: 600)
        .background(Theme.bg)
        .preferredColorScheme(.light)
        .onAppear { state.refreshStatuses() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshStatuses()
        }
        // Kick off the (mandatory) download as soon as the Models step appears.
        .onChange(of: state.step) {
            if state.step == .models, state.modelPhase == .idle {
                Task { await state.downloadModels() }
            }
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var content: some View {
        switch state.step {
        case .welcome: welcome
        case .permissions: permissions
        case .models: OnboardingProgressView(state: state)
        case .summary, .done: OnboardingSummaryView(store: settings, ollama: ollama)
        }
    }

    /// The summary engine the user has chosen on the summary step.
    private var chosenEngine: SummaryEngineKind {
        SummaryEngineKind.from(settings.config.summaryEngine)
    }

    /// Whether the chosen engine is ready to use right now: Ollama model installed, Apple available,
    /// or a Claude key present (the live connection test runs when Finish is pressed).
    private var summaryEngineReady: Bool {
        switch chosenEngine {
        case .ollama:
            return ollama.isInstalled(SummaryModels.resolved(override: settings.config.summaryModelID).id)
        case .apple:
            return SummaryEngineKind.apple.availability().isReady
        case .claude:
            return SecretStore.anthropicKey != nil
        }
    }

    /// One-line guidance shown next to a disabled Finish, so it's clear what's left to do.
    private var summaryHint: String? {
        guard state.step == .summary || state.step == .done, !summaryEngineReady else { return nil }
        switch chosenEngine {
        case .ollama: return "Download the model to finish"
        case .apple: return "Apple Intelligence is unavailable — pick another engine"
        case .claude: return "Add your Anthropic API key"
        }
    }

    /// Verify the Claude key with a tiny live call, then finish only if it works.
    private func verifyClaudeThenFinish() {
        verifyingClaude = true
        Task {
            do {
                _ = try await ClaudeClient(model: settings.config.summaryClaudeModel, maxTokens: 16)
                    .complete(system: "Reply with the single word OK.", prompt: "Connection test.")
                verifyingClaude = false
                onComplete()
            } catch {
                verifyingClaude = false
                ToastCenter.shared.error((error as? LocalizedError)?.errorDescription ?? "Connection failed")
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.sm) {
                Text("Welcome to Earwig")
                    .font(.largeTitle).fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
                Text("Private, on-device transcription and speaker identification for your meetings. Nothing leaves your Mac.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }
            byClearRoute.padding(.top, Spacing.xs)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissions: some View {
        // Dividers start under the title (past the icon tile) for a refined, grouped-list look.
        let dividerInset = Spacing.lg + 38 + Spacing.md
        return VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Grant permissions")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Earwig needs to hear both sides of a meeting. Microphone and System Audio are required; Speech Recognition is an optional fallback.")
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GlossyCard(padding: 0) {
                VStack(spacing: 0) {
                    OnboardingPermissionRow(
                        symbol: "mic.fill", title: "Microphone",
                        detail: "Records your voice (your side of the call).",
                        isRequired: true, status: state.microphone,
                        onGrant: { Task { await state.requestMicrophone() } },
                        onOpenSettings: { PermissionsService.openSettings(for: .microphone) })
                        .padding(.horizontal, Spacing.lg)

                    Hairline().padding(.leading, dividerInset)

                    OnboardingPermissionRow(
                        symbol: "speaker.wave.2.fill", title: "System Audio Recording",
                        detail: "Captures the other participants’ audio. macOS will show a one-time prompt.",
                        isRequired: true, status: state.systemAudio,
                        onGrant: { state.requestSystemAudio() },
                        onOpenSettings: { PermissionsService.openSettings(for: .systemAudio) })
                        .padding(.horizontal, Spacing.lg)

                    Hairline().padding(.leading, dividerInset)

                    OnboardingPermissionRow(
                        symbol: "waveform", title: "Speech Recognition",
                        detail: "Only used as a fallback if the primary on-device model is unavailable.",
                        isRequired: false, status: state.speech,
                        onGrant: { Task { await state.requestSpeech() } },
                        onOpenSettings: { PermissionsService.openSettings(for: .speechRecognition) })
                        .padding(.horizontal, Spacing.lg)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var byClearRoute: some View {
        HStack(spacing: 0) {
            Text("by Clear").foregroundStyle(Theme.textSecondary)
            Text("Route").foregroundStyle(Theme.accent)
        }
        .font(.subheadline).fontWeight(.semibold)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Spacing.md) {
            stepDots
            Spacer()
            if let summaryHint {
                Text(summaryHint)
                    .font(.captionText)
                    .foregroundStyle(Theme.textTertiary)
            }
            primaryButton
        }
        .padding(.horizontal, Spacing.xl + Spacing.xs)
        .padding(.vertical, Spacing.lg)
        .background(Theme.bg)
        .overlay(Hairline(), alignment: .top)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch state.step {
        case .welcome:
            Button("Get Started") { state.advance() }
                .buttonStyle(PrimaryButtonStyle())
        case .permissions:
            Button("Continue") { state.advance() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!state.canContinueFromPermissions)
        case .models:
            Button("Continue") { state.advance() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!state.modelsReady)
        case .summary, .done:
            // Gate Finish on the chosen engine being ready, so the app is usable on first launch.
            switch chosenEngine {
            case .claude:
                Button(verifyingClaude ? "Testing…" : "Test & Finish") { verifyClaudeThenFinish() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(SecretStore.anthropicKey == nil || verifyingClaude)
            case .ollama, .apple:
                Button("Finish", action: onComplete)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!summaryEngineReady)
            }
        }
    }

    /// A flat progress strip (de-iOS-ified): short bars filled up to the current step.
    private var stepDots: some View {
        HStack(spacing: Spacing.xs) {
            ForEach([OnboardingState.Step.welcome, .permissions, .models, .summary], id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= state.step.rawValue ? Theme.accent : Theme.hairline)
                    .frame(width: 18, height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}
