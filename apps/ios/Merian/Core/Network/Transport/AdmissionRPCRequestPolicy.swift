import Foundation

/// The reviewed read-only RPCs are the only non-Edge admission routes.
enum AdmissionRPCRequestPolicy {
    enum Route: String {
        case allowance = "get_my_scan_admission_preview"
        case recipient = "get_my_identification_preflight"
        case reanalysisRecipient = "get_owned_observation_reanalysis_preflight"
    }

    static func url(baseURL: String, route: Route) throws -> URL {
        guard let base = SecureTransportPolicy.httpsURL(from: baseURL) else {
            throw MerianError.invalidURL
        }
        return base.appendingPathComponent("rest").appendingPathComponent("v1")
            .appendingPathComponent("rpc").appendingPathComponent(route.rawValue)
    }

    static func validateAllowanceRequest(_ request: URLRequest, baseURL: String) throws {
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let apiKey = request.value(forHTTPHeaderField: "apikey")
        guard request.httpMethod == "POST",
              request.url == (try url(baseURL: baseURL, route: .allowance)),
              authorization?.hasPrefix("Bearer ") == true,
              authorization.map({ String($0.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) })?.isEmpty == false,
              apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MerianError.invalidURL
        }
    }
}
