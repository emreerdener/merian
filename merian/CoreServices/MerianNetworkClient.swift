import Foundation

enum NetworkError: Error {
    case invalidURL
    case uploadFailed
    case invalidResponse
    case decodingFailed
}

// Removed GeminiFile structures as we are no longer using the Gemini File API directly.

// Removed IdentifyResponse as payloads securely decode via nested JSON mapping natively downstream.

struct PreSignedURLResponse: Codable {
    let urls: [PreSignedURL]
}

struct PreSignedURL: Codable {
    let fileName: String
    let signedUrl: String
    let objectKey: String
}

class MerianNetworkClient {
    static let shared = MerianNetworkClient()
    
    // Configurable endpoints structurally pulled from explicit targets rather than ProcessInfo on iOS
    private let supabaseUrl = MerianEnvironment.supabaseUrl
    private let supabaseAnonKey = MerianEnvironment.supabaseAnonKey
    
    // Step 2: Supabase Inference
    func analyzeSubject(r2ObjectKey: String, depthScaleText: String?, gpsLatitude: Double?, gpsLongitude: Double?, weatherCondition: String?) async throws -> Data {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/identify")!
        
        var request = URLRequest(url: functionUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            var activeJWT = try? await SupabaseManager.shared.getActiveJWT()
            if activeJWT == nil {
                print("⚠️ MerianNetworkClient: Active JWT missing. Forcing local Ghost Session auth.")
                await SupabaseManager.shared.initializeGhostSession()
                activeJWT = try? await SupabaseManager.shared.getActiveJWT()
            }
            guard let finalJWT = activeJWT else {
                throw NetworkError.invalidResponse
            }
            request.setValue("Bearer \(finalJWT)", forHTTPHeaderField: "Authorization")
        } catch {
            print("⚠️ MerianNetworkClient: Critical Auth Failure: \(error.localizedDescription)")
            throw NetworkError.invalidResponse
        }
        
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let payload: [String: Any?] = [
            "r2ObjectKey": r2ObjectKey,
            "user_id": deviceId,
            "mimeType": "image/jpeg",
            "depthScaleText": depthScaleText,
            "gpsLatitude": gpsLatitude,
            "gpsLongitude": gpsLongitude,
            "weatherCondition": weatherCondition
        ]
        
        // Remove nils
        let cleanPayload = payload.compactMapValues { $0 }
        request.httpBody = try JSONSerialization.data(withJSONObject: cleanPayload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errString = String(data: data, encoding: .utf8) ?? "Unknown"
            print("🚨 SUPABASE EDGE FAILED [\(httpResponse.statusCode)]: \(errString)")
            throw NetworkError.invalidResponse
        }
        
        return data
    }
    
    // Step 3: Pre-Signed URLs
    func generateUploadURLs(fileNames: [String]) async throws -> [PreSignedURL] {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/generate-upload-urls")!
        
        var request = URLRequest(url: functionUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            var activeJWT = try? await SupabaseManager.shared.getActiveJWT()
            if activeJWT == nil {
                await SupabaseManager.shared.initializeGhostSession()
                activeJWT = try? await SupabaseManager.shared.getActiveJWT()
            }
            guard let finalJWT = activeJWT else {
                throw NetworkError.invalidResponse
            }
            request.setValue("Bearer \(finalJWT)", forHTTPHeaderField: "Authorization")
        } catch {
            throw NetworkError.invalidResponse
        }
        
        let payload: [String: Any] = ["fileNames": fileNames]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errString = String(data: data, encoding: .utf8) ?? "Unknown"
            print("🚨 GENERATE URLS FAILED [\(httpResponse.statusCode)]: \(errString)")
            throw NetworkError.invalidResponse
        }
        
        let res = try JSONDecoder().decode(PreSignedURLResponse.self, from: data)
        return res.urls
    }
    
    // Step 4: Permanent Archive
    func uploadToR2(url: String, data: Data, mimeType: String = "image/jpeg") async throws {
        guard let signedUrl = URL(string: url) else { throw NetworkError.invalidURL }
        
        var request = URLRequest(url: signedUrl)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.uploadFailed
        }
        
        if httpResponse.statusCode != 200 {
            let errString = String(data: data, encoding: .utf8) ?? "Unknown"
            print("🚨 R2 UPLOAD FAILED [\(httpResponse.statusCode)]: \(errString)")
            throw NetworkError.uploadFailed
        }
    }
}
