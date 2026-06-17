import Foundation

/// Sends feedback via the Resend API. Key baked into Info.plist at build time (`build.sh`).
struct ResendClient: Sendable {
    static let apiURL = URL(string: "https://api.resend.com/emails")!
    // Shared onboarding sender — no domain verification needed, but only delivers to account owner.
    static let fromAddress = "Earwig Feedback <onboarding@resend.dev>"
    // To send to other addresses, verify a domain at resend.com/domains and update fromAddress.
    static let recipient = "navnit.anuth@outlook.com"

    enum ResendError: Error, LocalizedError {
        case notConfigured
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Feedback sending isn't set up in this build."
            case .http(let code, let message):
                return message.isEmpty ? "Sending failed (HTTP \(code))." : message
            }
        }
    }

    static var apiKey: String? {
        let key = Bundle.main.infoDictionary?["EarwigResendKey"] as? String
        return (key?.isEmpty ?? true) ? nil : key
    }

    // MARK: - Request body (pure / testable)

    struct RequestBody: Encodable, Equatable {
        let from: String
        let to: [String]
        let subject: String
        let text: String
        let reply_to: String?
    }

    static func subject(for feedback: Feedback) -> String {
        let mood = feedback.mood == .happy ? "😀" : "☹️"
        let category: String
        switch feedback.category {
        case .general: category = "💬"
        case .bug: category = "🐞"
        case .feature: category = "✨"
        }
        return "\(mood)\(category) Earwig feedback: \(feedback.category.label) (\(feedback.mood.label))"
    }

    static func bodyText(for feedback: Feedback, version: String) -> String {
        var lines = [
            "Mood: \(feedback.mood.label)",
            "Type: \(feedback.category.label)",
            "",
            feedback.trimmedMessage,
            "",
            "--",
            "Sent from Earwig \(version)",
        ]
        if !feedback.trimmedEmail.isEmpty {
            lines.append("Reply to: \(feedback.trimmedEmail)")
        }
        return lines.joined(separator: "\n")
    }

    static func requestBody(for feedback: Feedback, version: String) -> RequestBody {
        let email = feedback.trimmedEmail
        return RequestBody(
            from: fromAddress,
            to: [recipient],
            subject: subject(for: feedback),
            text: bodyText(for: feedback, version: version),
            reply_to: email.isEmpty ? nil : email
        )
    }

    // MARK: - Send

    func send(_ feedback: Feedback, version: String) async throws {
        guard let key = Self.apiKey else { throw ResendError.notConfigured }

        let body = Self.requestBody(for: feedback, version: version)
        var req = URLRequest(url: Self.apiURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ResendError.http(-1, error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ResendError.http(http.statusCode, Self.errorMessage(from: data))
        }
    }

    static func errorMessage(from data: Data) -> String {
        struct ErrorEnvelope: Decodable { let message: String }
        if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data), !env.message.isEmpty {
            return env.message
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
