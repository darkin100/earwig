import Darwin
import Foundation
import Observation

/// Samples system-wide CPU load (all cores), 0...1.
/// Per-process would be misleading: transcription runs on the Neural Engine, summaries in Ollama.
@Observable @MainActor
final class CPUMonitor {
    private(set) var usage: Double = 0 // 0...1 across all cores

    private var loop: Task<Void, Never>?
    private var previous: host_cpu_load_info?

    func start() {
        guard loop == nil else { return }
        previous = CPUMonitor.cpuTicks()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { break }
                self?.sample()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        previous = nil
    }

    private func sample() {
        guard let now = CPUMonitor.cpuTicks() else { return }
        defer { previous = now }
        guard let old = previous else { return }
        let user = Double(now.cpu_ticks.0 &- old.cpu_ticks.0)
        let system = Double(now.cpu_ticks.1 &- old.cpu_ticks.1)
        let idle = Double(now.cpu_ticks.2 &- old.cpu_ticks.2)
        let nice = Double(now.cpu_ticks.3 &- old.cpu_ticks.3)
        let total = user + system + idle + nice
        usage = total > 0 ? min(1, max(0, (user + system + nice) / total)) : 0
    }

    nonisolated static func cpuTicks() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}
