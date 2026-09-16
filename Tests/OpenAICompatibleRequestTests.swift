import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func expectThrows(_ message: String, _ body: () throws -> Void) {
    do {
        try body()
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    } catch {
        // Expected
    }
}

@main
struct OpenAICompatibleRequestTests {
    @MainActor
    static func main() {
        checkEndpointResolution()
        checkRequestShape()
        checkContentParsing()
        checkModelParsing()
        checkResponseErrorMapping()
        print("OpenAICompatibleRequestTests passed")
    }

    private static func checkEndpointResolution() {
        expect(OpenAICompatibleEndpoint.chatCompletions(baseURL: "https://api.openai.com/v1")?.absoluteString
               == "https://api.openai.com/v1/chat/completions",
               "A /v1 base URL should be extended with the chat completions path")
        expect(OpenAICompatibleEndpoint.chatCompletions(baseURL: "https://api.openai.com/v1/")?.absoluteString
               == "https://api.openai.com/v1/chat/completions",
               "A trailing slash should not duplicate the path separator")
        expect(OpenAICompatibleEndpoint.chatCompletions(baseURL: "https://api.groq.com/openai/v1")?.absoluteString
               == "https://api.groq.com/openai/v1/chat/completions",
               "Longer base paths should be preserved")
        expect(OpenAICompatibleEndpoint.chatCompletions(baseURL: "http://localhost:11434/v1")?.absoluteString
               == "http://localhost:11434/v1/chat/completions",
               "Local http endpoints should be accepted")
        expect(OpenAICompatibleEndpoint.chatCompletions(baseURL: "http://localhost:11434/v1/chat/completions")?.absoluteString
               == "http://localhost:11434/v1/chat/completions",
               "A base URL already pointing at the endpoint should be used as-is")
        expect(OpenAICompatibleEndpoint.models(baseURL: "https://api.openai.com/v1")?.absoluteString
               == "https://api.openai.com/v1/models",
               "The models endpoint should sit next to chat completions")

        expect(OpenAICompatibleEndpoint.chatCompletions(baseURL: "") == nil,
               "An empty base URL has no endpoint")
        expect(OpenAICompatibleEndpoint.chatCompletions(baseURL: "   ") == nil,
               "A blank base URL has no endpoint")
        expect(OpenAICompatibleEndpoint.chatCompletions(baseURL: "api.openai.com/v1") == nil,
               "A base URL without a scheme has no endpoint")
        expect(OpenAICompatibleEndpoint.chatCompletions(baseURL: "ftp://api.openai.com/v1") == nil,
               "Only http and https base URLs are supported")
    }

    @MainActor
    private static func checkRequestShape() {
        do {
            let request = try OpenAICompatibleService.makeRequest(
                base64Image: "encoded-image",
                promptContent: "Return LaTeX",
                model: "gpt-4o",
                baseURL: "https://api.openai.com/v1",
                apiKey: "sk-test"
            )

            expect(request.httpMethod == "POST", "Requests should use POST")
            expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                   "Requests should be JSON")
            expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test",
                   "Requests should carry the API key as a bearer token")

            guard let body = request.httpBody,
                  let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                fputs("FAIL: Request should contain a JSON body\n", stderr)
                exit(1)
            }

            expect(payload["model"] as? String == "gpt-4o", "The payload should carry the model")
            expect(payload["max_tokens"] as? Int == OpenAICompatibleService.maxOutputTokens,
                   "The payload should carry the output token limit")

            guard let messages = payload["messages"] as? [[String: Any]],
                  messages.count == 2 else {
                fputs("FAIL: The payload should contain a system and a user message\n", stderr)
                exit(1)
            }

            expect(messages[0]["role"] as? String == "system", "The prompt should be the system message")
            expect(messages[0]["content"] as? String == "Return LaTeX",
                   "The system message should carry the prompt text")
            expect(messages[1]["role"] as? String == "user", "The image should be the user message")

            guard let parts = messages[1]["content"] as? [[String: Any]],
                  let imageURL = parts.first?["image_url"] as? [String: Any],
                  let url = imageURL["url"] as? String else {
                fputs("FAIL: The user message should contain an image_url part\n", stderr)
                exit(1)
            }
            expect(parts.first?["type"] as? String == "image_url", "The image part should be typed")
            expect(url == "data:image/png;base64,encoded-image",
                   "The image should be sent inline as a PNG data URL")

            let keyless = try OpenAICompatibleService.makeRequest(
                base64Image: "encoded-image",
                promptContent: "Prompt",
                model: "llama3.2",
                baseURL: "http://localhost:11434/v1",
                apiKey: ""
            )
            expect(keyless.value(forHTTPHeaderField: "Authorization") == nil,
                   "Local endpoints should be called without an Authorization header")

            expectThrows("A request without a model should fail") {
                _ = try OpenAICompatibleService.makeRequest(
                    base64Image: "encoded-image",
                    promptContent: "Prompt",
                    model: "  ",
                    baseURL: "https://api.openai.com/v1",
                    apiKey: "sk-test"
                )
            }
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func checkContentParsing() {
        let plain = #"{"choices":[{"message":{"role":"assistant","content":"  Sum of squares  "}}]}"#
        do {
            let content = try OpenAICompatibleService.parseContent(from: Data(plain.utf8))
            expect(content == "Sum of squares", "Content should be trimmed")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }

        let parts = #"{"choices":[{"message":{"content":[{"type":"text","text":"a + b"}]}}]}"#
        expect((try? OpenAICompatibleService.parseContent(from: Data(parts.utf8))) == "a + b",
               "Content parts should be joined")

        let empty = #"{"choices":[{"message":{"content":"   "}}]}"#
        expectThrows("Empty content should fail to parse") {
            _ = try OpenAICompatibleService.parseContent(from: Data(empty.utf8))
        }

        let failure = #"{"error":{"message":"model not found"}}"#
        expectThrows("An error body should fail to parse") {
            _ = try OpenAICompatibleService.parseContent(from: Data(failure.utf8))
        }

        expectThrows("A non-JSON body should fail to parse") {
            _ = try OpenAICompatibleService.parseContent(from: Data("<html>".utf8))
        }
    }

    @MainActor
    private static func checkModelParsing() {
        let payload = #"{"data":[{"id":"z-model"},{"id":"a-model"}]}"#
        let models = (try? OpenAICompatibleService.parseModels(from: Data(payload.utf8))) ?? []
        expect(models == ["a-model", "z-model"], "Model identifiers should be sorted")

        expectThrows("An empty model list should fail") {
            _ = try OpenAICompatibleService.parseModels(from: Data(#"{"data":[]}"#.utf8))
        }
        expectThrows("A model list without data should fail") {
            _ = try OpenAICompatibleService.parseModels(from: Data(#"{"object":"list"}"#.utf8))
        }
    }

    private static func checkResponseErrorMapping() {
        let unauthorized = Data(#"{"error":{"message":"Incorrect API key provided"}}"#.utf8)
        switch AIProviderError.fromResponse(statusCode: 401, data: unauthorized) {
        case .apiKeyInvalid(let message):
            expect(message == "Incorrect API key provided",
                   "The provider message should be surfaced for invalid keys")
        default:
            fputs("FAIL: 401 responses should map to an invalid key error\n", stderr)
            exit(1)
        }

        switch AIProviderError.fromResponse(statusCode: 403, data: Data()) {
        case .apiKeyInvalid(let message):
            expect(message == nil, "403 responses without a body should carry no message")
        default:
            fputs("FAIL: 403 responses should map to an invalid key error\n", stderr)
            exit(1)
        }

        switch AIProviderError.fromResponse(statusCode: 500, data: Data(#"{"error":"boom"}"#.utf8)) {
        case .apiError(let message):
            expect(message == "boom", "Provider error text should be reported as an API error")
        default:
            fputs("FAIL: Unmapped failures should map to an API error\n", stderr)
            exit(1)
        }

        switch AIProviderError.fromResponse(statusCode: 500, data: Data()) {
        case .apiError(let message):
            expect(message == "API request failed with status 500",
                   "Status codes should be reported when the provider sends no message")
        default:
            fputs("FAIL: Unmapped failures should map to an API error\n", stderr)
            exit(1)
        }
    }
}
