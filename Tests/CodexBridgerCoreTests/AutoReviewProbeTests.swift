import Foundation
import XCTest
@testable import CodexBridgerCore

/// Seam: AutoReviewProbe public API — request construction, verdict mapping, and
/// the prober actor driven by a stubbed URLProtocol (no real network is touched).
///
/// Expected values come from the reference probe (/tmp/approval-test/probe_final2.sh),
/// which was calibrated against a real Codex harness call: the reviewer runs on the
/// chat/completions wire with response_format json_schema, a per-model strict
/// override, and an approval-shaped schema whose only key is "decision".
final class AutoReviewProbeTests: XCTestCase {

    private func request(
        bearer: String? = "sk-test",
        headers: [String: String] = [:],
        query: [String: String] = [:],
        modelSlug: String = "kimi-k2.7-code",
        strict: Bool = true,
        wire: AutoReviewWire = .responses
    ) -> AutoReviewProbeRequest {
        AutoReviewProbeRequest(
            baseURL: "https://api.example.com/v1",
            bearerToken: bearer,
            httpHeaders: headers,
            queryParams: query,
            modelSlug: modelSlug,
            strict: strict,
            wire: wire,
            timeout: 60
        )
    }
    // MARK: Request construction


    func testRequestCarriesBearerAndContentType() throws {
        let http = try request().makeURLRequest()
        XCTAssertEqual(http.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testRequestCarriesProviderHTTPHeaders() throws {
        let http = try request(headers: ["X-Tenant": "acme"]).makeURLRequest()
        XCTAssertEqual(http.value(forHTTPHeaderField: "X-Tenant"), "acme")
    }

    func testRequestOmitsAuthorizationWhenNoBearer() throws {
        let http = try request(bearer: nil).makeURLRequest()
        XCTAssertNil(http.value(forHTTPHeaderField: "Authorization"))
    }

    func testRequestCarriesProviderQueryParams() throws {
        let url = try request(query: ["api-version": "2024-10-21"]).makeURLRequest().url
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(url), resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(components.queryItems?.first { $0.name == "api-version" }?.value, "2024-10-21")
    }

    func testChatBodyCarriesApprovalPromptAndDecisionSchema() throws {
        let http = try request(wire: .chat).makeURLRequest()
        let body = try XCTUnwrap(http.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(object["model"] as? String, "kimi-k2.7-code")
        let format = try XCTUnwrap(object["response_format"] as? [String: Any])
        let jsonSchema = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(jsonSchema["name"] as? String, "approval_review")
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        let schema = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let decision = try XCTUnwrap(properties["decision"] as? [String: Any])
        XCTAssertEqual(decision["type"] as? String, "string")
        XCTAssertEqual((decision["enum"] as? [String])?.sorted(), ["allow", "deny"])
        // The prompts are the reviewer's real ones, so the context matches production.
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertTrue(
            (messages.first?["content"] as? String ?? "").contains("approval reviewer"),
            "the system prompt must state the reviewer role"
        )
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        XCTAssertTrue(
            (messages.last?["content"] as? String ?? "").contains("Command:"),
            "the user prompt must carry the command under review"
        )
    }

    /// The per-model strict override: the reference probe observed the harness
    /// sending strict=false for glm-5.3-flash, and the upstream rejecting true.
    func testStrictOverrideIsWrittenIntoTheChatRequest() throws {
        let http = try request(strict: false, wire: .chat).makeURLRequest()
        let body = try XCTUnwrap(http.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let format = try XCTUnwrap(object["response_format"] as? [String: Any])
        let jsonSchema = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["strict"] as? Bool, false)
    }

    func testStrictOverrideIsWrittenIntoTheResponsesRequest() throws {
        let http = try request(strict: false, wire: .responses).makeURLRequest()
        let body = try XCTUnwrap(http.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let text = try XCTUnwrap(object["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["strict"] as? Bool, false)
    }
    // MARK: Per-slug strict resolution

    /// The harness sends strict=false for glm-5.3-flash and the upstream
    /// rejects true for it, so the table must win over the request default.
    func testDefaultTableTurnsStrictOffForTheObservedModel() throws {
        let req = request()
        XCTAssertFalse(req.resolvedStrict(for: "glm-5.3-flash"))
        XCTAssertTrue(req.resolvedStrict(for: "kimi-k2.7-code"))
    }

    func testTableEntryBeatsTheRequestsOwnStrictValue() throws {
        let req = request(strict: true)
        XCTAssertFalse(req.resolvedStrict(for: "glm-5.3-flash"))
    }

    func testCallersOwnStrictValueStandsForModelsWithNoEntry() throws {
        let req = request(strict: false)
        XCTAssertFalse(req.resolvedStrict(for: "kimi-k2.7-code"))
    }

    /// The per-slug flag must reach the body when the probe runs, not just
    /// when makeURLRequest is called by hand.
    func testProbeOneSendsTheResolvedStrictFlag() async throws {
        StubURLProtocol.configure(statusCode: 200)
        StubURLProtocol.recordBodies = true
        defer { StubURLProtocol.recordBodies = false }
        let prober = AutoReviewProbe(
            session: AutoReviewProbe.session(for: StubURLProtocol.self),
            maxConcurrent: 1, timeout: 5
        )
        _ = try await prober.probeOne(request(), slug: "glm-5.3-flash")
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let text = try XCTUnwrap(object["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["strict"] as? Bool, false)
    }

    // MARK: Wire selection

    /// Codex's harness routes through the Responses API, so that is what a
    /// probe sends first; chat/completions is the fallback shape.
    func testRequestDefaultsToTheResponsesWire() throws {
        let http = try request().makeURLRequest()
        XCTAssertEqual(http.url?.absoluteString, "https://api.example.com/v1/responses")
        let body = try XCTUnwrap(http.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(object["text"], "the responses wire carries text.format")
        XCTAssertNil(object["messages"])
        XCTAssertNil(object["response_format"])
        let input = try XCTUnwrap(object["input"] as? [[String: Any]])
        XCTAssertEqual(input.first?["role"] as? String, "system")
        XCTAssertEqual(input.last?["role"] as? String, "user")
        XCTAssertTrue((input.last?["content"] as? String ?? "").contains("Command:"))
    }

    func testChatWireTargetsChatCompletions() throws {
        let http = try request(wire: .chat).makeURLRequest()
        XCTAssertEqual(http.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        let body = try XCTUnwrap(http.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(object["messages"])
        XCTAssertNotNil(object["response_format"])
        XCTAssertNil(object["text"])
        XCTAssertNil(object["input"])
    }

    // MARK: Verdict mapping

    /// The pass shape: a choice whose content is the JSON the schema demands.
    func testClassifyMarksAllowDecisionAsSupported() throws {
        let body = ##"{"output":[{"type":"message","content":[{"type":"output_text","text":"{\"decision\": \"allow\"}"}]}]}"##
        let outcome = AutoReviewProbe.status(
            slug: "m", statusCode: 200, body: Data(body.utf8), latencyMs: 820
        )
        XCTAssertEqual(outcome.status, .supported)
        XCTAssertEqual(outcome.latencyMs, 820)
    }

    func testClassifyMarksDenyDecisionAsSupported() throws {
        let body = ##"{"output":[{"type":"message","content":[{"type":"output_text","text":"{\"decision\":\"deny\"}"}]}]}"##
        let outcome = AutoReviewProbe.status(
            slug: "m", statusCode: 200, body: Data(body.utf8), latencyMs: 200
        )
        XCTAssertEqual(outcome.status, .supported)
    }

    /// Markdown fences around the JSON are tolerated, as the reference probe is.
    func testClassifyAcceptsFencedJSON() throws {
        let body = ##"{"output":[{"type":"message","content":[{"type":"output_text","text":"```json\n{\"decision\":\"allow\"}\n```"}]}]}"##
        let outcome = AutoReviewProbe.status(
            slug: "m", statusCode: 200, body: Data(body.utf8), latencyMs: 5
        )
        XCTAssertEqual(outcome.status, .supported)
    }

    /// HTTP 200 is not enough: wrong keys cannot be read as a verdict.
    func testClassifyRejectsWrongKeys() throws {
        let body = ##"{"output":[{"type":"message","content":[{"type":"output_text","text":"{\"decision\":\"allow\",\"reason\":\"x\"}"}]}]}"##
        let outcome = AutoReviewProbe.status(
            slug: "m", statusCode: 200, body: Data(body.utf8), latencyMs: 5
        )
        XCTAssertEqual(outcome.status, .unsupported)
        XCTAssertTrue(outcome.summary?.contains("wrong_keys") == true)
    }

    func testClassifyRejectsBadDecisionValue() throws {
        let body = ##"{"output":[{"type":"message","content":[{"type":"output_text","text":"{\"decision\":\"maybe\"}"}]}]}"##
        let outcome = AutoReviewProbe.status(
            slug: "m", statusCode: 200, body: Data(body.utf8), latencyMs: 5
        )
        XCTAssertEqual(outcome.status, .unsupported)
        XCTAssertTrue(outcome.summary?.contains("bad_decision") == true)
    }

    func testClassifyRejectsContentThatIsNotJSON() throws {
        let body = ##"{"output":[{"type":"message","content":[{"type":"output_text","text":"I cannot help"}]}]}"##
        let outcome = AutoReviewProbe.status(
            slug: "m", statusCode: 200, body: Data(body.utf8), latencyMs: 5
        )
        XCTAssertEqual(outcome.status, .unsupported)
        XCTAssertTrue(outcome.summary?.contains("not_json") == true)
    }

    func testClassifyReportsUpstreamErrorMessage() throws {
        let body = ##"{"error":{"message":"Upstream request failed: [invalid_request_error] This response_format type is unavailable now"}}"##
        let outcome = AutoReviewProbe.status(
            slug: "deepseek-v4-flash", statusCode: 400, body: Data(body.utf8), latencyMs: 300
        )
        XCTAssertEqual(outcome.status, .unsupported)
        XCTAssertTrue(outcome.summary?.contains("response_format type is unavailable") == true)
    }

    func testClassifyMarksUnauthorized() throws {
        let outcome = AutoReviewProbe.status(
            slug: "m", statusCode: 401, body: Data(#"{"error":"bad key"}"#.utf8), latencyMs: 120
        )
        XCTAssertEqual(outcome.status, .unauthorized)
    }

    func testClassifyMarksServerError() throws {
        let outcome = AutoReviewProbe.status(
            slug: "m", statusCode: 503, body: Data("gateway down".utf8), latencyMs: 900
        )
        XCTAssertEqual(outcome.status, .serverError)
    }

    // MARK: Wire fallback

    /// Responses is tried first (that is what Codex uses); a proxy without
    /// that endpoint must still be usable, so a missing endpoint falls back
    /// to chat/completions rather than reporting the model as broken.
    func testFallsBackToChatWhenTheResponsesEndpointIsMissing() async throws {
        StubURLProtocol.configure(statusCode: 404)
        StubURLProtocol.responder = { request in
            (request.url?.path.hasSuffix("/responses") ?? false) ? 404 : 200
        }
        defer { StubURLProtocol.responder = nil }
        let prober = AutoReviewProbe(
            session: AutoReviewProbe.session(for: StubURLProtocol.self),
            maxConcurrent: 1, timeout: 5
        )
        let outcome = try await prober.probeOne(request(), slug: "m")
        XCTAssertEqual(outcome.status, .supported)
        XCTAssertEqual(outcome.wire, .chat, "the fallback wire is reported")
    }

    func testDoesNotFallBackWhenTheModelItselfRefuses() async throws {
        StubURLProtocol.configure(statusCode: 400)
        StubURLProtocol.responder = { _ in 400 }
        defer { StubURLProtocol.responder = nil }
        let prober = AutoReviewProbe(
            session: AutoReviewProbe.session(for: StubURLProtocol.self),
            maxConcurrent: 1, timeout: 5
        )
        let outcome = try await prober.probeOne(request(), slug: "deepseek-v4-pro")
        XCTAssertEqual(outcome.status, .unsupported)
    }

    func testReportsResponsesWireWhenItWorks() async throws {
        StubURLProtocol.configure(statusCode: 200)
        StubURLProtocol.responder = { _ in 200 }
        defer { StubURLProtocol.responder = nil }
        let prober = AutoReviewProbe(
            session: AutoReviewProbe.session(for: StubURLProtocol.self),
            maxConcurrent: 1, timeout: 5
        )
        let outcome = try await prober.probeOne(request(), slug: "m")
        XCTAssertEqual(outcome.status, .supported)
        XCTAssertEqual(outcome.wire, .responses)
    }

    // MARK: Prober actor

    func testProbeReportsSupportedThroughStubbedSession() async throws {
        StubURLProtocol.configure(statusCode: 200)
        let prober = AutoReviewProbe(
            session: AutoReviewProbe.session(for: StubURLProtocol.self), maxConcurrent: 3, timeout: 5
        )
        let outcome = try await prober.probeOne(
            request(), slug: "kimi-k2.7-code"
        )
        XCTAssertEqual(outcome.slug, "kimi-k2.7-code")
        XCTAssertEqual(outcome.status, .supported)
    }

    func testProbeReportsUnsupportedThroughStubbedSession() async throws {
        StubURLProtocol.configure(
            statusCode: 400,
            body: Data(##"{"error":{"message":"This response_format type is unavailable now"}}"##.utf8)
        )
        let prober = AutoReviewProbe(
            session: AutoReviewProbe.session(for: StubURLProtocol.self), maxConcurrent: 3, timeout: 5
        )
        let outcome = try await prober.probeOne(request(), slug: "deepseek-v4-flash")
        XCTAssertEqual(outcome.status, .unsupported)
        XCTAssertEqual(outcome.summary, "This response_format type is unavailable now")
    }

    func testProbeReportsTimeoutWhenResponseNeverArrives() async throws {
        StubURLProtocol.configure(statusCode: 200, delay: 30)
        let prober = AutoReviewProbe(
            session: AutoReviewProbe.session(for: StubURLProtocol.self), maxConcurrent: 3, timeout: 0.4
        )
        let outcome = try await prober.probeOne(request(), slug: "slow")
        XCTAssertEqual(outcome.status, .timeout)
    }

    func testProbeReportsUnreachableOnTransportFailure() async throws {
        StubURLProtocol.configure(transportError: URLError(.cannotConnectToHost))
        let prober = AutoReviewProbe(
            session: AutoReviewProbe.session(for: StubURLProtocol.self), maxConcurrent: 3, timeout: 5
        )
        let outcome = try await prober.probeOne(request(), slug: "grok-4.7")
        XCTAssertEqual(outcome.status, .unreachable)
    }

    func testProbeAllRunsEverySlugAndKeepsOrder() async throws {
        StubURLProtocol.configure(statusCode: 200)
        let prober = AutoReviewProbe(
            session: AutoReviewProbe.session(for: StubURLProtocol.self), maxConcurrent: 3, timeout: 5
        )
        let results = try await prober.probeAll(
            request(), slugs: ["a", "b", "c", "d", "e"]
        )
        XCTAssertEqual(results.map(\.slug), ["a", "b", "c", "d", "e"])
        XCTAssertTrue(results.allSatisfy { $0.status == .supported })
    }
}

/// Stub transport: answers every request with a fixed status/body, optionally
/// after a delay or with a transport error. Registered per session in the tests.
final class StubURLProtocol: URLProtocol {
    static var statusCode = 200
    static var body = Data()
    static var delay: TimeInterval = 0
    static var transportError: URLError?
    /// Body of the last request, when recordBodies is on. URLSession may hand
    /// the body to the loader rather than to startLoading, so both paths are read.
    /// When set, the status code is decided from the request itself, so a test
    /// can answer the Responses endpoint differently from chat/completions.
    static var responder: ((URLRequest) -> Int)?
    static var lastBody: Data?
    static var recordBodies = false

    /// Configured explicitly before every test: static state that survives a
    /// previous test would make results order-dependent.
    static func configure(
        statusCode: Int = 200,
        body: Data = Data(##"{"output":[{"type":"message","content":[{"type":"output_text","text":"{\"decision\": \"allow\"}"}]}]}"##.utf8),
        delay: TimeInterval = 0,
        transportError: URLError? = nil
    ) {
        Self.statusCode = statusCode
        Self.body = body
        Self.delay = delay
        Self.transportError = transportError
    }

    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if Self.recordBodies { Self.lastBody = Self.bodyData(of: request) }
        // The body of work runs off the loading thread: a Thread.sleep here
        // would block the session's protocol queue and starve later tests.
        let respond = {
            if let error = Self.transportError {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let code = Self.responder?(self.request) ?? Self.statusCode
            let response = HTTPURLResponse(
                url: self.request.url!, statusCode: code,
                httpVersion: "HTTP/1.1", headerFields: nil
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Self.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if Self.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: respond)
        } else {
            respond()
        }
    }

    override func stopLoading() {}

    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}