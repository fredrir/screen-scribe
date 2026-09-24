import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct GeminiServiceRequestTests {
    @MainActor
    static func main() {
        do {
            let request = try GeminiService.makeRequest(
                base64Image: "encoded-image",
                apiKey: "test-api-key",
                promptContent: "Return LaTeX",
                model: "gemini-3.7-flash"
            )

            expect(request.url?.path.contains("/models/gemini-3.7-flash:generateContent") == true,
                   "Requests should use the selected Gemini 3.7 Flash model")
            expect(request.httpMethod == "POST", "Requests should use POST")

            guard let body = request.httpBody,
                  let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let generationConfig = payload["generationConfig"] as? [String: Any] else {
                fputs("FAIL: Request should contain a JSON generation config\n", stderr)
                exit(1)
            }

            expect(generationConfig["temperature"] == nil,
                   "Requests should omit the deprecated temperature parameter")
            expect(generationConfig["candidateCount"] == nil,
                   "Requests should omit the unsupported candidateCount parameter")
            expect(generationConfig["maxOutputTokens"] as? Int == 2048,
                   "Requests should retain the output token limit")

            do {
                _ = try GeminiService.makeRequest(
                    base64Image: "encoded-image", apiKey: "test-api-key", promptContent: "Return LaTeX", model: " ")
                fputs("FAIL: Requests without a model should be rejected\n", stderr)
                exit(1)
            } catch {}

            try checkModelList()
            print("GeminiServiceRequestTests passed")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func checkModelList() throws {
        let first = try GeminiService.makeModelsRequest(
            apiKey: "test-api-key", baseURL: Config.defaultGeminiBaseURL, pageToken: nil)
        expect(first.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000",
               "The model list should ask for the largest page")
        expect(first.value(forHTTPHeaderField: "x-goog-api-key") == "test-api-key",
               "The model list should send the key as a header")

        let next = try GeminiService.makeModelsRequest(
            apiKey: "test-api-key", baseURL: Config.defaultGeminiBaseURL, pageToken: "page-2")
        expect(next.url?.query?.contains("pageToken=page-2") == true, "Later pages should pass the page token")

        let page = #"""
        {"models":[
          {"name":"models/gemini-3.7-flash","supportedGenerationMethods":["generateContent","countTokens"]},
          {"name":"models/gemini-embedding-001","supportedGenerationMethods":["embedContent"]},
          {"name":"models/imagen-4.0-generate-001","supportedGenerationMethods":["predict"]}
        ],"nextPageToken":"page-2"}
        """#
        let parsed = try GeminiService.parseModels(from: Data(page.utf8))
        expect(parsed.models == ["gemini-3.7-flash"],
               "Only models that answer generateContent should be listed, without the models/ prefix")
        expect(parsed.nextPageToken == "page-2", "The next page token should be read")

        let last = try GeminiService.parseModels(from: Data(#"{"models":[],"nextPageToken":""}"#.utf8))
        expect(last.nextPageToken == nil, "An empty page token should end the listing")

        let rejected = Data(#"{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT"}}"#.utf8)
        do {
            _ = try GeminiService.parseModels(from: rejected)
            fputs("FAIL: Error bodies should be reported\n", stderr)
            exit(1)
        } catch AIProviderError.apiError(let message) {
            expect(message == "API key not valid.", "Gemini's error message should be surfaced")
        }
    }
}
