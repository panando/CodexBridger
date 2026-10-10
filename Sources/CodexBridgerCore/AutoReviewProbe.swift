import Foundation

/// Probes whether a provider's model can run Codex's auto-review sub-agent.
///
/// The reviewer needs a strict JSON-schema structured output, and not every
/// model or proxy accepts it: DeepSeek's endpoint answers 'response_format
/// type is unavailable', for example. A probe sends one tiny request per model
/// through the provider's Responses endpoint - the same shape Codex itself
/// uses, since every catalog this app writes sets wire_api = 'responses' -
/// and maps the answer to a status the UI can show.
///
/// Nothing here writes a file, touches Codex config, or keeps a credential:
/// the caller hands a token to a single call and the token dies with it.
/// Which wire a probe speaks.
///
/// Codex's harness routes approval reviews through the Responses API, so that
/// is what a probe sends first; chat/completions is the fallback shape for a
/// proxy that only exposes the legacy endpoint. Both were calibrated against
/// the reference probe.
public enum AutoReviewWire: String, Sendable, Equatable, Codable, CaseIterable {
    case responses
    case chat

    /// Appended to the provider's base URL, which already carries /v1.
    var pathSuffix: String {
        switch self {
        case .responses: return "/responses"
        case .chat: return "/chat/completions"
        }
    }
}

public struct AutoReviewProbeRequest: Sendable, Equatable {
    public var baseURL: String
    /// In-memory only. Never stored, never logged.
    public var bearerToken: String?
    /// Static headers from the provider config.
    public var httpHeaders: [String: String]
    /// Query params from the provider config.
    public var queryParams: [String: String]
    public var modelSlug: String
    /// Whether response_format.json_schema.strict is true. The harness sends
    /// strict=false for some models (glm-5.3-flash observed), so this is a
    /// per-model override rather than a constant.
    public var strict: Bool
    /// Which wire the probe speaks. Codex routes through Responses, so that is
    /// the default; chat/completions is the fallback for proxies that only
    /// expose the legacy shape.
    public var wire: AutoReviewWire
    /// Per-model strict overrides. A slug with an entry here wins over
    /// `strict`, because the harness sends strict=false for some models
    /// (glm-5.3-flash observed) and the upstream rejects true for them.
    public var strictOverrides: AutoReviewStrictOverrides
    public var timeout: TimeInterval

    public init(
        baseURL: String,
        bearerToken: String?,
        httpHeaders: [String: String] = [:],
        queryParams: [String: String] = [:],
        modelSlug: String,
        strict: Bool = true,
        wire: AutoReviewWire = .responses,
        strictOverrides: AutoReviewStrictOverrides = .default,
        timeout: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.httpHeaders = httpHeaders
        self.queryParams = queryParams
        self.modelSlug = modelSlug
        self.strict = strict
        self.wire = wire
        self.strictOverrides = strictOverrides
        self.timeout = timeout
    }
    /// The strict flag for one model: the table wins when it names the slug,
    /// otherwise the caller's own value stands.
    public func resolvedStrict(for slug: String) -> Bool {
        strictOverrides.entries[slug] ?? strict
    }

    /// The exact request Codex would make for this provider, reduced to one
    /// throwaway 'answer with JSON' turn.
    public func makeURLRequest() throws -> URLRequest {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: trimmedBase)
        if components?.scheme == nil {
            // A user-typed base_url can lack the scheme; fix it the way the
            // form validator does rather than producing a nil URL.
            components = URLComponents(string: "https://" + trimmedBase)
        }
        guard var components else { throw ProbeError.invalidBaseURL }
        let basePath = components.path
        components.path = basePath.isEmpty ? wire.pathSuffix : basePath + wire.pathSuffix
        if !queryParams.isEmpty {
            components.queryItems = queryParams
                .map { URLQueryItem(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
        }
        guard let url = components.url else { throw ProbeError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer " + bearerToken, forHTTPHeaderField: "Authorization")
        }
        for (name, value) in httpHeaders where !name.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body(), options: [.sortedKeys])
        return request
    }

    /// The reviewer prompts, taken from the reference probe that was
    /// calibrated against a real harness call: the reviewer must see the
    /// command it is judging, so the context matches production.
    static let reviewerSystemPrompt =
        "You are an approval reviewer for shell commands. Decide whether to allow"
        + " or deny execution. Respond with JSON only."
    static let reviewerCommand =
        "touch /Users/panando/AgenticProjects/Codex/.approval-test"

    /// The decision schema the reviewer must fill: one key, allow or deny.
    static var decisionSchema: [String: Any] {
        [
            "type": "object",
            "properties": ["decision": ["type": "string",
                                           "enum": ["allow", "deny"]]],
            "required": ["decision"]
        ]
    }

    private var format: [String: Any] {
        [
            "type": "json_schema",
            "name": "approval_review",
            "strict": strict,
            "schema": Self.decisionSchema
        ]
    }

    /// The two conversation turns the reviewer sees. The command under review
    /// is in the user turn so the context matches a real harness call.
    private var turns: [[String: Any]] {
        [
            ["role": "system", "content": Self.reviewerSystemPrompt],
            ["role": "user", "content": "Command: " + Self.reviewerCommand]
        ]
    }

    private func body() -> [String: Any] {
        switch wire {
        case .responses:
            // Responses wire: turns live in `input`, the schema in text.format.
            return [
                "model": modelSlug,
                "input": turns,
                "text": ["format": format]
            ]
        case .chat:
            // Legacy wire: turns in `messages`, the schema nested inside
            // response_format.json_schema.
            return [
                "model": modelSlug,
                "messages": turns,
                "response_format": [
                    "type": "json_schema",
                    "json_schema": [
                        "name": "approval_review",
                        "strict": strict,
                        "schema": Self.decisionSchema
                    ]
                ]
            ]
        }
    }

    public enum ProbeError: Error, LocalizedError {
        case invalidBaseURL

        public var errorDescription: String? {
            switch self {
            case .invalidBaseURL: return "Base URL 无法拼出探测地址"
            }
        }
    }
}

/// What one probe answered. Kept without the request, so a cached outcome can
/// never carry the token that produced it.
public struct AutoReviewProbeOutcome: Sendable, Equatable, Codable {
    public var slug: String
    public var status: AutoReviewProbeStatus
    public var latencyMs: Int?
    /// Short, human-readable reason for anything but 'supported'.
    public var summary: String?
    /// Which wire answered. Responses is the one Codex uses; chat/completions
    /// appears only when the provider has no Responses endpoint and the probe
    /// fell back, or when the caller asked for the legacy shape.
    public var wire: AutoReviewWire?

    public init(
        slug: String,
        status: AutoReviewProbeStatus,
        latencyMs: Int?,
        summary: String?,
        wire: AutoReviewWire? = nil
    ) {
        self.slug = slug
        self.status = status
        self.latencyMs = latencyMs
        self.summary = summary
        self.wire = wire
    }
}

public enum AutoReviewProbeStatus: String, Sendable, Equatable, Codable, CaseIterable {
    /// Strict JSON schema accepted; the model can run auto-review.
    case supported
    /// The model answers, but refuses strict JSON schema output.
    case unsupported
    /// The key was rejected (401/403): a credential problem, not a model problem.
    case unauthorized
    /// 429 or 5xx: the provider or proxy is unhealthy right now.
    case serverError
    /// No answer within the timeout.
    case timeout
    /// The endpoint could not be reached at all.
    case unreachable
    /// The provider has no such endpoint (404/405), so another wire may work.
    case missingEndpoint
}

/// Runs probes against one provider.
///
/// An actor so concurrent probes cannot corrupt shared state; the session is
/// injected so tests substitute a stubbed transport and no test ever touches
/// the network.
public actor AutoReviewProbe {

    private let session: URLSession
    private let maxConcurrent: Int
    private let timeout: TimeInterval
    /// Test seam: when set, no request is sent; the closure answers with the
    /// HTTP status code that slug would have received. Production leaves it nil.
    private let responder: (@Sendable (String) -> Int)?

    public init(
        session: URLSession = .shared,
        maxConcurrent: Int = 3,
        timeout: TimeInterval = 60,
        responder: (@Sendable (String) -> Int)? = nil
    ) {
        self.session = session
        self.maxConcurrent = max(1, maxConcurrent)
        self.timeout = max(0.1, timeout)
        self.responder = responder
    }

    /// Builds a session whose traffic is answered by protocolClass.
    /// Tests use it; production uses the default actor initialiser.
    public static func session(
        for protocolClass: URLProtocol.Type,
        configuration: URLSessionConfiguration = .ephemeral
    ) -> URLSession {
        configuration.protocolClasses = [protocolClass]
        return URLSession(configuration: configuration)
    }

    // MARK: One model

    /// Same as probeOne but never throws: a request that cannot even be
    /// built is reported as an outcome, so a batch keeps running.
    func probeOneGuarded(_ request: AutoReviewProbeRequest, slug: String) async -> AutoReviewProbeOutcome {
        do {
            return try await probeOne(request, slug: slug)
        } catch {
            return AutoReviewProbeOutcome(
                slug: slug, status: .unreachable, latencyMs: nil,
                summary: Self.brief(error.localizedDescription)
            )
        }
    }

    /// Probes one model on the Responses wire, falling back to
    /// chat/completions when the provider has no Responses endpoint at all.
    ///
    /// Responses first is deliberate: that is the wire Codex itself uses. The
    /// fallback exists so a proxy that only exposes the legacy endpoint is
    /// still usable instead of every model being reported as broken. A model
    /// that answers and refuses (400) is *not* retried: that is a verdict
    /// about the model, identical on both wires.
    public func probeOne(
        _ request: AutoReviewProbeRequest,
        slug: String
    ) async throws -> AutoReviewProbeOutcome {
        let primary = try await attempt(request, slug: slug, wire: request.wire)
        guard primary.status == .missingEndpoint else {
            return primary
        }
        let fallback = request.wire == .chat ? AutoReviewWire.responses : .chat
        return try await attempt(request, slug: slug, wire: fallback)
    }

    /// One wire, one request.

    private func attempt(
        _ request: AutoReviewProbeRequest,
        slug: String,
        wire: AutoReviewWire
    ) async throws -> AutoReviewProbeOutcome {
        var request = request
        request.modelSlug = slug
        request.timeout = timeout
        request.wire = wire
        request.strict = request.resolvedStrict(for: slug)
        let clock = ContinuousClock()
        let started = clock.now
        // The responder seam decides the status code without a network round
        // trip; the mapping below stays the single code path.
        if let responder {
            let code = responder(slug)
            let body: Data = (200...299).contains(code)
                ? Data(##"{"output":[{"type":"message","content":[{"type":"output_text","text":"{\"decision\": \"allow\"}"}]}]}"##.utf8)
                : Data(##"{"error":{"message":"This response_format type is unavailable now"}}"##.utf8)
            let latency = started.duration(to: clock.now).milliseconds
            return Self.status(
                slug: slug, statusCode: code, body: body,
                latencyMs: latency, wire: wire
            )
        }
        let urlRequest = try request.makeURLRequest()
        do {
            let (data, response) = try await session.data(for: urlRequest)
            let latency = started.duration(to: clock.now).milliseconds
            return Self.status(
                slug: slug,
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                body: data,
                latencyMs: latency,
                wire: wire
            )
        } catch let error as URLError where error.code == .timedOut {
            return AutoReviewProbeOutcome(
                slug: slug, status: .timeout, latencyMs: nil,
                summary: "超时未响应", wire: wire
            )
        } catch let error as URLError {
            return AutoReviewProbeOutcome(
                slug: slug, status: .unreachable, latencyMs: nil,
                summary: Self.brief(error.localizedDescription), wire: wire
            )
        } catch {
            return AutoReviewProbeOutcome(
                slug: slug, status: .unreachable, latencyMs: nil,
                summary: Self.brief(error.localizedDescription), wire: wire
            )
        }
    }

    // MARK: Many models

    /// Probes every slug, in the given order, at most maxConcurrent at a time.
    /// Cancellation stops the run and throws.
    public func probeAll(
        _ request: AutoReviewProbeRequest,
        slugs: [String]
    ) async throws -> [AutoReviewProbeOutcome] {
        var results: [AutoReviewProbeOutcome] = []
        var index = 0
        while index < slugs.count {
            try Task.checkCancellation()
            let batch = Array(slugs[index..<min(index + maxConcurrent, slugs.count)])
            let outcomes = try await withTaskGroup(
                of: AutoReviewProbeOutcome.self
            ) { group in
                for slug in batch {
                    group.addTask { await self.probeOneGuarded(request, slug: slug) }
                }
                var collected: [AutoReviewProbeOutcome] = []
                for await outcome in group { collected.append(outcome) }
                return collected
            }
            results.append(contentsOf: outcomes)
            index += batch.count
        }
        // TaskGroup completion order is not input order; restore it.
        let bySlug = Dictionary(grouping: results, by: { $0.slug })
        return slugs.compactMap { slug in bySlug[slug]?.first }
    }

    // MARK: Status mapping

    /// Maps a raw answer to a status. Pure, so every branch is testable
    /// without a network.
    public static func status(
        slug: String,
        statusCode: Int,
        body: Data,
        latencyMs: Int?,
        wire: AutoReviewWire? = nil
    ) -> AutoReviewProbeOutcome {
        switch statusCode {
        case 200...299:
            // HTTP 200 is not enough: the reviewer must produce the schema’s
            // own JSON, exactly one "decision" key, value allow or deny.
            // Verdicts follow the reference probe so a failing model names
            // the reason (not_json, wrong_keys, bad_decision, …).
            switch Self.verdict(of: body) {
            case let .pass(decoded):
                return AutoReviewProbeOutcome(
                    slug: slug, status: .supported, latencyMs: latencyMs,
                    summary: decoded, wire: wire
                )
            case let .fail(reason):
                return AutoReviewProbeOutcome(
                    slug: slug, status: .unsupported, latencyMs: latencyMs,
                    summary: reason, wire: wire
                )
            }
        case 404, 405:
            return AutoReviewProbeOutcome(
                slug: slug, status: .missingEndpoint, latencyMs: latencyMs,
                summary: "HTTP " + String(statusCode), wire: wire
            )
        case 400, 422:
            return AutoReviewProbeOutcome(
                slug: slug, status: .unsupported, latencyMs: latencyMs,
                summary: Self.errorSummary(in: body), wire: wire
            )
        case 401, 403:
            return AutoReviewProbeOutcome(
                slug: slug, status: .unauthorized, latencyMs: latencyMs,
                summary: Self.errorSummary(in: body), wire: wire
            )
        case 429, 500...599:
            return AutoReviewProbeOutcome(
                slug: slug, status: .serverError, latencyMs: latencyMs,
                summary: Self.errorSummary(in: body), wire: wire
            )
        default:
            return AutoReviewProbeOutcome(
                slug: slug, status: .unsupported, latencyMs: latencyMs,
                summary: "HTTP " + String(statusCode), wire: wire
            )
        }
    }

    /// One verdict of the reference probe: the answer parses as the reviewer’s
    /// own JSON, or the reason it does not.
    enum ProbeVerdict {
        case pass(String)
        case fail(String)
    }

    /// Maps a chat/completions answer to the reference probe’s verdict.
    ///
    /// The check order and the reason strings follow /tmp/approval-test/probe_final2.sh:
    /// upstream error → missing content → markdown fences stripped → not JSON →
    /// not an object → wrong keys → bad decision value.
    static func verdict(of body: Data, wire: AutoReviewWire? = nil) -> ProbeVerdict {
        let text = String(data: body, encoding: .utf8) ?? ""
        let parsed = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        // The wire decides where the assistant text lives; the body's own shape
        // answers it when the caller does not know.
        let resolved = wire ?? Self.shape(of: parsed)
        if let message = parsed?["error"] as? [String: Any],
           let detail = message["message"] as? String {
            return .fail("upstream_error:" + String(detail.prefix(120)))
        }
        if let message = parsed?["error"] as? String {
            return .fail("upstream_error:" + String(message.prefix(120)))
        }
        guard let content = Self.assistantText(parsed, wire: resolved) else {
            if parsed == nil {
                return .fail("invalid_json:" + String(text.prefix(60)))
            }
            return .fail("no_choices_or_no_content")
        }
        let stripped = Self.withoutCodeFences(content)
        guard let data = stripped.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let verdict = object as? [String: Any] else {
            let snippet = String(stripped.replacingOccurrences(of: "\n", with: " ").prefix(60))
            return .fail("not_json:" + snippet)
        }
        if Set(verdict.keys) != ["decision"] {
            return .fail("wrong_keys:" + verdict.keys.sorted().joined(separator: ","))
        }
        guard let decision = verdict["decision"] as? String,
              ["allow", "deny"].contains(decision) else {
            return .fail("bad_decision:" + String(describing: verdict["decision"]))
        }
        return .pass(decision)
    }

    /// choices[0].message.content, the only place a verdict can live.
    /// Which wire an answer speaks, from its shape alone.
    static func shape(of object: [String: Any]?) -> AutoReviewWire {
        if object?["output"] != nil { return .responses }
        return .chat
    }

    /// The assistant text of an answer, in the shape that wire uses.
    ///
    /// A Responses answer may interleave reasoning items with the message;
    /// only the message's output_text counts, which is exactly the filter the
    /// reference verifier applies.
    static func assistantText(_ object: [String: Any]?, wire: AutoReviewWire) -> String? {
        let raw: String?
        switch wire {
        case .responses: raw = responsesText(object)
        case .chat: raw = chatText(object)
        }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// output[*] of a Responses answer: reasoning items skipped, message
    /// content joined.
    private static func responsesText(_ object: [String: Any]?) -> String? {
        guard let output = object?["output"] as? [[String: Any]] else { return nil }
        var chunks: [String] = []
        for item in output {
            if item["type"] as? String == "reasoning" { continue }
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for piece in content
            where (piece["type"] as? String) == "output_text"
                || (piece["type"] as? String) == "text" {
                if let text = piece["text"] as? String { chunks.append(text) }
            }
        }
        return chunks.isEmpty ? nil : chunks.joined(separator: "\n")
    }

    /// choices[0].message.content, the only place a verdict can live.
    private static func chatText(_ object: [String: Any]?) -> String? {
        guard let object,
              let choices = object["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }
        return content
    }
    /// Drops markdown code fences, which a model may wrap around its JSON.
    private static func withoutCodeFences(_ text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        let kept = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First sentence-ish of the provider's error, capped so a whole HTML
    /// error page cannot blow up a table row.
    static func brief(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(120)) + "…"
    }

    /// The provider's own error text, capped so an HTML error page cannot
    /// blow up a row.
    static func errorSummary(in body: Data) -> String {
        let raw: String
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                raw = message
            } else if let message = object["message"] as? String {
                raw = message
            } else if let error = object["error"] as? String {
                raw = error
            } else {
                raw = object["detail"] as? String ?? "未知错误"
            }
        } else {
            raw = String(data: body, encoding: .utf8) ?? "未知错误"
        }
        return brief(raw)
    }
}

// MARK: - Persisted scan result

/// What a 一键检测 run found for one provider, kept so the next launch does not
/// have to probe again.
///
/// Deliberately credential-free: it stores slugs, statuses, latencies and the
/// provider's own error text. The token used for the probes dies with the run,
/// so a cache file can never leak one.
public struct AutoReviewScanCache: Sendable, Equatable, Codable {
    public var providerID: String
    /// The slugs that were probed, normalised (sorted, unique). Compared against
    /// the current model list to decide staleness.
    public var scannedSlugs: [String]
    public var scannedAt: Date
    public var outcomes: [AutoReviewProbeOutcome]

    public init(
        providerID: String,
        scannedSlugs: [String],
        scannedAt: Date,
        outcomes: [AutoReviewProbeOutcome]
    ) {
        self.providerID = providerID
        self.scannedSlugs = Self.normalise(scannedSlugs)
        self.scannedAt = scannedAt
        self.outcomes = outcomes
    }

    /// Builds one from a probe run.
    public init(providerID: String, slugs: [String], scannedAt: Date = Date(), outcomes: [AutoReviewProbeOutcome]) {
        self.init(
            providerID: providerID,
            scannedSlugs: Self.normalise(slugs),
            scannedAt: scannedAt,
            outcomes: outcomes
        )
    }

    /// True when the current model list no longer matches what was probed, so
    /// the cached pass/fail cannot be trusted.
    public func isStale(currentSlugs: [String]) -> Bool {
        scannedSlugs != Self.normalise(currentSlugs)
    }

    /// Models that accepted strict JSON schema, in the order they were probed.
    public var supportedSlugs: [String] {
        outcomes.filter { $0.status == .supported }.map(\.slug)
    }

    public func outcome(for slug: String) -> AutoReviewProbeOutcome? {
        outcomes.first { $0.slug == slug }
    }

    static func normalise(_ slugs: [String]) -> [String] {
        Array(Set(slugs)).sorted()
    }
}

// MARK: - Latency helper

private extension Duration {
    /// Milliseconds as an Int, flooring at 0.
    var milliseconds: Int {
        let components = self.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return max(0, Int((seconds * 1000).rounded()))
    }
}