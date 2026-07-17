import Foundation

/// Calls the shared, no-key Cloudflare Worker AI proxy for the nightly grogginess insight.
/// The proxy is stateless — it processes the request and replies, keeping no server-side
/// history; only the on-device 14-day grogginess log persists anywhere.
enum AIProxyClient {
    static let textEndpoint = URL(string: "https://apps-ai-proxy.s0533495227.workers.dev/text")!

    enum ClientError: Error {
        case notEnoughHistory
        case http(Int)
        case emptyResponse
    }

    /// Sends the last 14 days of `{anchorDurationHours, grogginessRating}` pairs and asks for
    /// one plain sentence suggesting a specific alternate anchor duration.
    static func nightlyInsight(entries: [GrogginessEntry]) async -> Result<String, Error> {
        let recent = GrogginessLog.lastDays(entries)
        guard recent.count >= 3 else {
            return .failure(ClientError.notEnoughHistory)
        }

        let pairs = recent.map {
            "{\"anchorDurationHours\": \($0.anchorDurationHours), \"grogginessRating\": \($0.rating)}"
        }.joined(separator: ", ")

        let systemPrompt = """
        You are a sleep-data analyst inside the Driftwake alarm app. You will be given up to \
        14 days of paired data points: the anchor duration used that night (hours after true \
        sleep onset, not clock time) and the user's next-morning grogginess rating from 1 \
        (very groggy) to 5 (sharp and rested). Find any correlation between anchor duration \
        and grogginess, then reply with exactly ONE short, plain, encouraging sentence \
        recommending a specific alternate anchor duration to try tonight. No preamble, no \
        bullet points, no disclaimers, no markdown — just the one sentence.
        """
        let userPrompt = "Data: [\(pairs)]"

        let requestBody: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        do {
            var request = URLRequest(url: textEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                return .failure(ClientError.http(status))
            }
            guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
                  let content = decoded.choices.first?.message.content,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(ClientError.emptyResponse)
            }
            return .success(content.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .failure(error)
        }
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}
