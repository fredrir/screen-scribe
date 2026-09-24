import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

/// Answers requests from a route table keyed by "METHOD /path", or "POST /path model" for JSON bodies.
private final class StubServer: URLProtocol {
    nonisolated(unsafe) static var routes: [String: String] = [:]
    nonisolated(unsafe) static var received: [URLRequest] = []

    static func session(routes: [String: String]) -> URLSession {
        self.routes = routes
        received = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.received.append(request)
        let body = Self.routes[Self.routeKey(for: request)]
        let response = HTTPURLResponse(
            url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func routeKey(for request: URLRequest) -> String {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        guard let stream = request.httpBodyStream else { return "\(method) \(path)" }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        let model = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["model"] ?? ""
        return "\(method) \(path) \(model)"
    }
}

@main
struct VisionModelDiscoveryTests {
    @MainActor
    static func main() async {
        checkInlineParsing()
        checkLiteLLMParsing()
        checkLMStudioParsing()
        checkOllamaParsing()
        await checkDiscovery()
        print("VisionModelDiscoveryTests passed")
    }

    private static let plainModels = #"{"object":"list","data":[{"id":"llava","object":"model"},{"id":"llama3","object":"model"}]}"#

    private static func checkInlineParsing() {
        let openRouter = #"""
        {"data":[
          {"id":"openai/gpt-4o","architecture":{"modality":"text+image->text","input_modalities":["text","image"]}},
          {"id":"deepseek/deepseek-chat","architecture":{"modality":"text->text","input_modalities":["text"]}}
        ]}
        """#
        expect(VisionModelDiscovery.parseInlineVisionModels(from: Data(openRouter.utf8)) == ["openai/gpt-4o"],
               "OpenRouter input modalities should mark vision models")

        let mistral = #"""
        {"data":[
          {"id":"pixtral-large-latest","capabilities":{"completion_chat":true,"vision":true}},
          {"id":"codestral-latest","capabilities":{"completion_chat":true,"vision":false}}
        ]}
        """#
        expect(VisionModelDiscovery.parseInlineVisionModels(from: Data(mistral.utf8)) == ["pixtral-large-latest"],
               "Mistral capabilities should mark vision models")

        let toolCapabilities = #"{"data":[{"id":"qwen2-vl","capabilities":["tool_use"]}]}"#
        expect(VisionModelDiscovery.parseInlineVisionModels(from: Data(toolCapabilities.utf8)) == nil,
               "Capability lists that don't mention vision should not count as an answer")
        expect(VisionModelDiscovery.parseInlineVisionModels(from: Data(plainModels.utf8)) == nil,
               "Plain OpenAI model lists should not count as an answer")
    }

    private static func checkLiteLLMParsing() {
        let info = #"""
        {"data":[
          {"model_name":"zai-org/GLM-5.3-Flash","model_info":{"supports_vision":true,"mode":null}},
          {"model_name":"zai-org/GLM-5.3-Flash","model_info":{"supports_vision":true}},
          {"model_name":"openai/gpt-oss-120b","model_info":{"supports_vision":null}},
          {"model_name":"Qwen/Qwen3-Embedding-8B","model_info":{"mode":"embedding"}},
          {"model_name":"text-only","model_info":{"supports_vision":false}}
        ]}
        """#
        expect(VisionModelDiscovery.parseLiteLLMVisionModels(from: Data(info.utf8)) == ["zai-org/GLM-5.3-Flash"],
               "LiteLLM should keep only vision models, once each")

        let unknown = #"{"data":[{"model_name":"custom","model_info":{"supports_vision":null}}]}"#
        expect(VisionModelDiscovery.parseLiteLLMVisionModels(from: Data(unknown.utf8)) == nil,
               "LiteLLM without any vision flags should not count as an answer")
    }

    private static func checkLMStudioParsing() {
        let v1 = #"""
        {"models":[
          {"type":"llm","key":"google/gemma-4-26b-a4b","capabilities":{"vision":true,"trained_for_tool_use":true}},
          {"type":"llm","key":"deepseek-r1","capabilities":{"vision":false}},
          {"type":"embedding","key":"text-embedding-nomic"}
        ]}
        """#
        expect(VisionModelDiscovery.parseLMStudioVisionModels(from: Data(v1.utf8)) == ["google/gemma-4-26b-a4b"],
               "LM Studio's v1 capabilities should mark vision models")

        let v0 = #"""
        {"object":"list","data":[
          {"id":"qwen2-vl-7b-instruct","type":"vlm"},
          {"id":"meta-llama-3.1-8b-instruct","type":"llm"},
          {"id":"text-embedding-nomic-embed-text-v1.5","type":"embeddings"}
        ]}
        """#
        expect(VisionModelDiscovery.parseLMStudioVisionModels(from: Data(v0.utf8)) == ["qwen2-vl-7b-instruct"],
               "LM Studio's v0 model type should mark vision models")
    }

    private static func checkOllamaParsing() {
        let vision = #"{"details":{"family":"llama"},"capabilities":["completion","vision"]}"#
        let text = #"{"details":{"family":"llama"},"capabilities":["completion","tools"]}"#
        expect(VisionModelDiscovery.parseOllamaSupportsVision(from: Data(vision.utf8)) == true,
               "Ollama's vision capability should be detected")
        expect(VisionModelDiscovery.parseOllamaSupportsVision(from: Data(text.utf8)) == false,
               "Ollama models without the vision capability should be rejected")
        expect(VisionModelDiscovery.parseOllamaSupportsVision(from: Data("{}".utf8)) == nil,
               "Responses without capabilities should not count as an answer")
    }

    @MainActor
    private static func checkDiscovery() async {
        let liteLLM = await visionModels(routes: [
            "GET /v1/models": plainModels,
            "GET /v1/model/info": #"{"data":[{"model_name":"llava","model_info":{"supports_vision":true}}]}"#,
        ])
        expect(liteLLM.models == ["llava"], "LiteLLM proxies should be asked through /model/info")
        expect(StubServer.received.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer key" },
               "Every probe should carry the API key")

        let lmStudio = await visionModels(routes: [
            "GET /v1/models": plainModels,
            "GET /api/v1/models": #"{"models":[{"key":"llava","capabilities":{"vision":true}}]}"#,
        ])
        expect(lmStudio.models == ["llava"], "LM Studio should be asked through its native model list")

        let ollama = await visionModels(routes: [
            "GET /v1/models": plainModels,
            "POST /api/show llava": #"{"capabilities":["completion","vision"]}"#,
            "POST /api/show llama3": #"{"capabilities":["completion"]}"#,
        ])
        expect(ollama.models == ["llava"], "Ollama should be asked about each model")

        let unknown = await visionModels(routes: ["GET /v1/models": plainModels])
        expect(unknown.models == ["llama3", "llava"], "Servers without vision info should list every model")
        expect(StubServer.received.filter { $0.url?.path == "/api/show" }.count == 1,
               "A non-Ollama server should only be asked about one model")

        let textOnly = await visionModels(routes: [
            "GET /v1/models": plainModels,
            "GET /v1/model/info": #"{"data":[{"model_name":"llama3","model_info":{"supports_vision":false}}]}"#,
        ])
        expect(textOnly.error == .noVisionModels, "Servers without vision models should say so")

        let rejected = await visionModels(routes: [:])
        expect(rejected.error == .other, "A failing /models request should be reported as before")

        print("  discovery ok")
    }

    private enum Failure: Equatable {
        case noVisionModels, other
    }

    @MainActor
    private static func visionModels(routes: [String: String]) async -> (models: [String], error: Failure?) {
        let service = OpenAICompatibleService(session: StubServer.session(routes: routes), maxRetries: 0)
        do {
            return (try await service.fetchModels(baseURL: "http://llm.test/v1", apiKey: "key"), nil)
        } catch VisionModelListError.noVisionModels {
            return ([], .noVisionModels)
        } catch {
            return ([], .other)
        }
    }
}
