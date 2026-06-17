import SwiftUI
import Observation

/// App-wide transient feedback. Call `ToastCenter.shared.success("Copied")` (or `.error`,
/// `.warning`, `.info`) from any action; `ToastOverlay` renders the current toast.
@Observable @MainActor
final class ToastCenter {
    static let shared = ToastCenter()
    private init() {}

    enum Style {
        case success, error, warning, info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: return Theme.green
            case .error: return Theme.danger
            case .warning: return Theme.amber
            case .info: return Theme.accent
            }
        }
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: Style
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Style = .success) {
        current = Toast(message: message, style: style)
        dismissTask?.cancel()
        dismissTask = Task {
            // Errors linger a little longer so they can be read.
            try? await Task.sleep(for: .seconds(style == .error ? 4 : 2.2))
            guard !Task.isCancelled else { return }
            current = nil
        }
    }

    func success(_ m: String) { show(m, style: .success) }
    func error(_ m: String) { show(m, style: .error) }
    func warning(_ m: String) { show(m, style: .warning) }
    func info(_ m: String) { show(m, style: .info) }
}
