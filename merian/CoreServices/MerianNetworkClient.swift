import Foundation

enum NetworkError: Error {
    case invalidURL
    case uploadFailed
    case invalidResponse
    case decodingFailed
}

struct GeminiFileResponse: Codable {
    let file: GeminiFile
}

struct GeminiFile: Codable {
    let uri: String
    let name: String
}

struct IdentifyResponse: Codable {
    let result: String // Depending on schema structure
}

struct PreSignedURLResponse: Codable {
    let urls: [PreSignedURL]
}

struct PreSignedURL: Codable {
    let fileName: String
    let signedUrl: String
}

class MerianNetworkClient {
    static let shared = MerianNetworkClient()
    
    // Configurable endpoints structurally pulled from explicit targets rather than ProcessInfo on iOS
    private let geminiApiKey = MerianEnvironment.geminiApiKey
    private let supabaseUrl = MerianEnvironment.supabaseUrl
    private let supabaseAnonKey = MerianEnvironment.supabaseAnonKey
    
    // Step 1: Ephemeral Upload to Gemini File API
    // Returns the lightweight fileUri
    func uploadToGeminiFileAPI(imageData: Data, mimeType: String = "image/jpeg") async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/upload/v1beta/files?uploadType=media&key=\(geminiApiKey)"
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NetworkError.uploadFailed
        }
        
        let fileResponse = try JSONDecoder().decode(GeminiFileResponse.self, from: data)
        return fileResponse.file.uri
    }
    
    // Step 2: Supabase Inference
    func analyzeSubject(fileUris: [String], depthScaleText: String?, gpsLatitude: Double?, gpsLongitude: Double?, weatherCondition: String?) async throws -> String {
        let uri = fileUris.first ?? ""
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
        
        let payload: [String: Any?] = [
            "geminiFileUri": uri,
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
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }
        
        let res = try JSONDecoder().decode(IdentifyResponse.self, from: data)
        return res.result
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
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
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
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NetworkError.uploadFailed
        }
    }
}
