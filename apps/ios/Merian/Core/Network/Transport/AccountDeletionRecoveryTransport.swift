import Foundation
import os

/// Public capability continuation only. It never acquires user Auth or accepts a caller route.
struct AccountDeletionRecoveryTransport {
    private let baseURL: String
    private let supabaseAnonKey: String
    private let sessionTransport: PinnedNetworkTransport

    init(baseURL: String, publishableKey: String, sessionTransport: PinnedNetworkTransport) {
        self.baseURL = baseURL
        supabaseAnonKey = publishableKey
        self.sessionTransport = sessionTransport
    }

    func post(body: () throws -> Data) async throws -> (data: Data, statusCode: Int) {
        guard MerianEnvironment.isSupabaseConfigured else {
            MerianLog.network.error("Network request blocked because Supabase environment configuration is incomplete.")
            throw MerianError.invalidURL
        }
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "recover-account-deletion")
        let bodyData = try body()
        let (data, response) = try await performPublicAccountDeletionRecoveryRequest(url: url, body: bodyData)
        return (data, response.statusCode)
    }

    private func performPublicAccountDeletionRecoveryRequest(
        url: URL,
        body: Data,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sessionTransport.data(for: request)
        } catch let urlError as URLError {
            try Task.checkCancellation()
            let transientCodes: Set<URLError.Code> = [
                .timedOut,
                .networkConnectionLost,
                .cannotConnectToHost,
                .dnsLookupFailed,
                .notConnectedToInternet
            ]
            if transientCodes.contains(urlError.code), !isRetry {
                try await Task.sleep(for: .seconds(2))
                return try await performPublicAccountDeletionRecoveryRequest(
                    url: url,
                    body: body,
                    isRetry: true
                )
            }
            throw urlError
        }

        try Task.checkCancellation()
        guard data.count <= 64 * 1024,
              let httpResponse = response as? HTTPURLResponse else {
            throw MerianError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode >= 500, !isRetry {
                try await Task.sleep(for: .seconds(2))
                return try await performPublicAccountDeletionRecoveryRequest(
                    url: url,
                    body: body,
                    isRetry: true
                )
            }
            let message = String(data: data, encoding: .utf8) ?? ""
            throw MerianError.httpError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
        return (data, httpResponse)
    }
}
