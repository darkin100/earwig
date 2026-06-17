import Foundation
import Observation

/// Observable Ollama state: daemon reachability, installed models, pull progress.
@Observable @MainActor
final class OllamaState {
    enum Reach: Equatable { case unknown, reachable, unreachable }

    /// Pull lifecycle for a model tag.
    enum Pull: Equatable {
        case pulling(Double)
        case failed(String)
    }

    private(set) var reach: Reach = .unknown
    private(set) var installed: [OllamaClient.Model] = []
    private(set) var pulls: [String: Pull] = [:]

    func refresh() async {
        let client = OllamaClient()
        if let models = try? await client.installedModels() {
            reach = .reachable
            installed = models.sorted { $0.name < $1.name }
        } else {
            reach = .unreachable
            installed = []
        }
    }

    func isInstalled(_ tag: String) -> Bool { installed.contains { $0.name == tag } }

    func pull(for tag: String) -> Pull? { pulls[tag] }

    func pullModel(_ tag: String) {
        if case .pulling = pulls[tag] { return }
        pulls[tag] = .pulling(0)
        Task {
            do {
                try await OllamaClient().pull(model: tag) { [weak self] fraction in
                    Task { @MainActor in self?.pulls[tag] = .pulling(fraction) }
                }
                pulls[tag] = nil
                await refresh()
            } catch {
                pulls[tag] = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
