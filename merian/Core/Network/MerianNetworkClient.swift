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
    
    // Step 1.5: Generic Request Abstraction
    private func performAuthenticatedRequest(
        url: URL,
        method: String,
        body: Data? = nil,
        timeoutInterval: TimeInterval = 30.0,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutInterval)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = body
        }
        
        do {
            var activeJWT = try? await SupabaseManager.shared.getActiveJWT()
            if activeJWT == nil {
                if UserDefaults.standard.bool(forKey: "Merian_HasAuthenticatedOAuth") {
                    print("🚨 MerianNetworkClient: Disconnected OAuth user. Throwing to force manual UI login.")
                    throw NetworkError.invalidResponse
                }
                print("⚠️ MerianNetworkClient: JWT missing, retrying Ghost initialization...")
                await SupabaseManager.shared.initializeGhostSession()
                activeJWT = try? await SupabaseManager.shared.getActiveJWT()
            }
            guard let finalJWT = activeJWT else {
                print("⚠️ MerianNetworkClient: Active JWT missing or expired after retry. Throwing NetworkError.")
                throw NetworkError.invalidResponse
            }
            request.setValue("Bearer \(finalJWT)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        } catch {
            print("⚠️ MerianNetworkClient: Critical Auth Failure: \(error.localizedDescription)")
            throw NetworkError.invalidResponse
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errString = String(data: data, encoding: .utf8) ?? "Unknown"
            print("🚨 SUPABASE EDGE FAILED [\(httpResponse.statusCode)]: \(errString)")
            
            // Self-Healing Zombie Session Trap safely managed
            if httpResponse.statusCode == 401 && !isRetry {
                let hasAuthenticatedOAuth = UserDefaults.standard.bool(forKey: "Merian_HasAuthenticatedOAuth")
                if hasAuthenticatedOAuth {
                    print("🚨 NATIVE SESSION EXPIRED. Blocking Ghost overwrite to force UI re-authentication.")
                    throw NetworkError.invalidResponse
                }
                
                let isGuest = await SupabaseManager.shared.isGuestUser
                if isGuest {
                    print("🚨 ZOMBIE SESSION DETECTED. Purging local auth cache and regenerating...")
                    await SupabaseManager.shared.signOut()
                    await SupabaseManager.shared.initializeGhostSession()
                    
                    print("⏳ Waiting 1.5s for Kong API Gateway to sync new ES256 signature...")
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    
                    return try await performAuthenticatedRequest(url: url, method: method, body: body, timeoutInterval: timeoutInterval, isRetry: true)
                } else {
                    print("🚨 NATIVE SESSION EXPIRED. Failing gracefully to allow re-authentication.")
                    throw NetworkError.invalidResponse
                }
            }
            
            throw NetworkError.invalidResponse
        }
        
        return (data, httpResponse)
    }
    
    // Step 2: Supabase Inference
    func analyzeSubject(r2ObjectKey: String?, base64ImageData: String?, telemetry: CaptureTelemetry) async throws -> Data {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/identify")!
        
        // CRITICAL: Prevent iOS from returning cached 401s during the self-healing retry loop
        var request = URLRequest(url: functionUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            var activeJWT = try? await SupabaseManager.shared.getActiveJWT()
            if activeJWT == nil {
                if UserDefaults.standard.bool(forKey: "Merian_HasAuthenticatedOAuth") {
                    print("🚨 MerianNetworkClient: Disconnected OAuth user. Throwing to force manual UI login.")
                    throw NetworkError.invalidResponse
                }
                print("⚠️ MerianNetworkClient: JWT missing, retrying Ghost initialization...")
                await SupabaseManager.shared.initializeGhostSession()
                activeJWT = try? await SupabaseManager.shared.getActiveJWT()
            }
            guard let finalJWT = activeJWT else {
                print("⚠️ MerianNetworkClient: Active JWT missing or expired after retry. Throwing NetworkError.")
                throw NetworkError.invalidResponse
            }
            request.setValue("Bearer \(finalJWT)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        } catch {
            print("⚠️ MerianNetworkClient: Critical Auth Failure: \(error.localizedDescription)")
            throw NetworkError.invalidResponse
        }
        
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let deviceLocale = Locale.current.language.languageCode?.identifier ?? "en"
        let currentMonth = Calendar.current.component(.month, from: Date())
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timeOfDay = formatter.string(from: Date())
        
        let depthScaleText = telemetry.subjectDistanceInMeters.map { String(format: "%.1f meters", $0) }
        let payload: [String: Any?] = [
            "r2ObjectKey": r2ObjectKey,
            "imageBase64": base64ImageData,
            "user_id": deviceId,
            "mimeType": "image/jpeg",
            "depthScaleText": depthScaleText,
            "gpsLatitude": telemetry.gpsLatitude,
            "gpsLongitude": telemetry.gpsLongitude,
            "gpsElevation": telemetry.gpsElevation,
            "semanticLocation": telemetry.locationName,
            "weatherCondition": telemetry.weatherCondition,
            "weatherTemperatureF": telemetry.weatherTemperatureF,
            "deviceLocale": deviceLocale,
            "currentMonth": currentMonth,
            "timeOfDay": timeOfDay,
            "cameraPitchDegrees": telemetry.cameraPitchDegrees,
            "compassHeading": telemetry.compassHeading,
            "relativeHumidity": telemetry.relativeHumidity,
            "uvIndex": telemetry.uvIndex,
            "isFlashFired": telemetry.isFlashFired
        ]
        
        // Remove nils
        let cleanPayload = payload.compactMapValues { $0 }
        let bodyData = try JSONSerialization.data(withJSONObject: cleanPayload)
        
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return data
    }
    
    // Step 3: Pre-Signed URLs
    func generateUploadURLs(fileNames: [String]) async throws -> [PreSignedURL] {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/generate-upload-urls")!
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let payload: [String: Any] = ["fileNames": fileNames, "user_id": deviceId]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        
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
    
    // Step 5: Data Deletion
    func deleteScan(scanId: String) async throws {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/delete-scan")!
        let payload: [String: Any] = ["scanId": scanId]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        print("✅ Scan deleted sequentially successfully from Cloud Edge")
    }
    
    // Step 6: Full Account Erasure
    func safeDeleteAccount() async throws {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/safe-delete")!
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST")
        print("✅ Account physically destroyed across PostgreSQL and Cloudflare R2")
    }
    
    // Step 7: Export Darwin Core Archive
    func exportDwcA(scope: String = "user") async throws -> URL {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/export-dwca")!
        let payload: [String: Any] = ["exportScope": scope, "includePreciseCoordinates": true]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData, timeoutInterval: 120.0)
        
        struct ExportResponse: Codable {
            let exportUrl: String
        }
        
        guard let result = try? JSONDecoder().decode(ExportResponse.self, from: data), let url = URL(string: result.exportUrl) else {
            throw NetworkError.decodingFailed
        }
        
        return url
    }
}
