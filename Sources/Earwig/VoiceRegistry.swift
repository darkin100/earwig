import Foundation

struct VoiceIdentity: Codable, Equatable {
    let name: String
    let isMe: Bool
    var samples: [[Float]]
}

struct VoiceRegistry: Codable, Equatable {
    private(set) var identities: [VoiceIdentity] = []

    mutating func enroll(name: String, embedding: [Float], isMe: Bool, maxSamples: Int) {
        let cap = max(1, maxSamples)
        if let i = identities.firstIndex(where: { $0.name == name }) {
            var samples = identities[i].samples + [embedding]
            if samples.count > cap { samples.removeFirst(samples.count - cap) }
            identities[i] = VoiceIdentity(name: name, isMe: isMe, samples: samples)
        } else {
            identities.append(VoiceIdentity(name: name, isMe: isMe, samples: [embedding]))
        }
    }

    func match(_ embedding: [Float], threshold: Float) -> (identity: VoiceIdentity, score: Float)? {
        let candidates = identities.map { $0.samples }
        guard let m = VoiceMatcher.bestMatch(embedding, among: candidates, threshold: threshold) else {
            return nil
        }
        return (identities[m.index], m.score)
    }

    mutating func forget(_ name: String) {
        identities.removeAll { $0.name == name }
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> VoiceRegistry {
        guard FileManager.default.fileExists(atPath: url.path) else { return VoiceRegistry() }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VoiceRegistry.self, from: data)
    }
}
