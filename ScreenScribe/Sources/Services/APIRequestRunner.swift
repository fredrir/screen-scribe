import Foundation

/// Sends requests using the retry policy shared by the provider clients: lost connections are
/// retried with a linear backoff, everything else is reported to the caller.
struct APIRequestRunner {
    private let session: URLSession
    private let maxRetries: Int
    private let initialDelay: UInt64

    init(session: URLSession = .shared, maxRetries: Int = 3, initialDelay: UInt64 = 1_000_000_000) {
        self.session = session
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
    }

    /// Performs the request. Non-2xx responses are handed back to the caller to interpret.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var retryCount = 0

        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIProviderError.invalidResponse
                }
                return (data, httpResponse)
            } catch let error as AIProviderError {
                throw error
            } catch {
                guard retryCount < maxRetries, Self.isTransient(error) else {
                    throw AIProviderError.networkError(error)
                }
                retryCount += 1
                try await Task.sleep(nanoseconds: initialDelay * UInt64(retryCount))
            }
        }
    }

    private static func isTransient(_ error: Error) -> Bool {
        (error as? URLError)?.code == .networkConnectionLost
    }
}
