import Foundation
import Testing

@Suite("Network Endpoint Architecture")
struct MerianNetworkArchitectureTests {
    @Test func fieldTripsStayInTheirEndpointOwner() throws {
        let root = try networkRoot()
        let endpoint = try String(
            contentsOf: root.appendingPathComponent("Endpoints/MerianNetworkClient+FieldTrips.swift"),
            encoding: .utf8
        )
        let client = try String(contentsOf: root.appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8)

        #expect(endpoint.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(endpoint.contains("extension MerianNetworkClient"))
        #expect(endpoint.contains("private func getFieldTripTemplate(identifier:"))
        #expect(endpoint.contains("private func updateFieldTripLifecycle("))
        #expect(client.contains("func performAuthenticatedJSONPost<Response: Decodable>"))
        for token in [
            "URLSession", "SupabaseManager", "Task {", "Task.detached",
            "static let shared", "performAuthenticatedRequest(", "endpointURL("
        ] {
            #expect(!endpoint.contains(token), "Endpoint extensions must not own \(token)")
        }

        let declarations = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
        let matches = declarations.matches(in: endpoint, range: NSRange(endpoint.startIndex..., in: endpoint))
        #expect(matches.count == 29)
        for match in matches {
            let range = try #require(Range(match.range(at: 1), in: endpoint))
            #expect(!client.contains("func \(endpoint[range])("))
        }
    }

    @Test func sharedTransportImplementationRemainsPrivate() throws {
        let client = try String(
            contentsOf: networkRoot().appendingPathComponent("MerianNetworkClient.swift"),
            encoding: .utf8
        )
        for declaration in [
            "private let supabaseUrl", "private let supabaseAnonKey",
            "private var activeSession:", "private lazy var session:",
            "private func endpointURL(", "private func makeExploreDecoder()",
            "private func performAuthenticatedRequest(", "private func performAuthenticatedTransport(",
            "private func requestPayloadAuthUserID(", "private func refreshActiveSessionForRetry()"
        ] {
            #expect(client.contains(declaration), "Transport boundary widened: \(declaration)")
        }
        let start = try #require(client.range(of: "    func performAuthenticatedJSONPost<"))
        let end = try #require(client.range(of: "\n    }", range: start.upperBound..<client.endIndex))
        let bridge = String(client[start.lowerBound..<end.upperBound])
        for token in [
            "try endpointURL(function)", "JSONSerialization.data(withJSONObject: payload)",
            "method: \"POST\"", "timeoutInterval: timeoutInterval",
            "makeExploreDecoder().decode(responseType, from: data)"
        ] {
            #expect(bridge.contains(token))
        }
        #expect(bridge.components(separatedBy: "performAuthenticatedRequest(").count == 2)
        #expect(bridge.contains("idempotencyKey: String? = nil"))
        #expect(bridge.contains("idempotencyKey: idempotencyKey"))
        #expect(bridge.contains("decodingFailure: MerianError? = nil"))
        let transport = try #require(bridge.range(of: "try await performAuthenticatedRequest("))
        let decodingScope = try #require(bridge.range(of: "do {"))
        #expect(transport.upperBound < decodingScope.lowerBound)
        #expect(bridge.contains("if let decodingFailure { throw decodingFailure }"))
        #expect(bridge.contains("throw error"))
        #expect(!bridge.contains("Task"))

        let voidStart = try #require(client.range(of: "    func performAuthenticatedJSONPost(\n"))
        let voidEnd = try #require(client.range(of: "\n    }", range: voidStart.upperBound..<client.endIndex))
        let voidBridge = String(client[voidStart.lowerBound..<voidEnd.upperBound])
        for token in [
            "try endpointURL(function)", "JSONSerialization.data(withJSONObject: payload)",
            "method: \"POST\"", "timeoutInterval: timeoutInterval", "_ = try await performAuthenticatedRequest("
        ] {
            #expect(voidBridge.contains(token))
        }
        #expect(voidBridge.components(separatedBy: "performAuthenticatedRequest(").count == 2)
        for token in ["decode", "catch", "Task", "success"] {
            #expect(!voidBridge.contains(token), "Body-ignoring transport must not add \(token)")
        }
    }

    @Test func communityIdentificationStaysInItsEndpointOwner() throws {
        let root = try networkRoot()
        let endpoint = try String(
            contentsOf: root.appendingPathComponent("Endpoints/MerianNetworkClient+CommunityIdentification.swift"),
            encoding: .utf8
        )
        let client = try String(contentsOf: root.appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8)
        let expectedMethods: Set<String> = [
            "getCommunityIdentificationFeed", "getCommunityIdentificationActivity",
            "getCommunityIdentificationDetail", "updateCommunityIdentificationRequest",
            "searchCommunityTaxa", "submitCommunityIdentification",
            "withdrawCommunityIdentification", "restoreCommunityIdentification"
        ]
        let declarations = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
        let matches = declarations.matches(in: endpoint, range: NSRange(endpoint.startIndex..., in: endpoint))
        let actualMethods = try matches.map { match in
            String(endpoint[try #require(Range(match.range(at: 1), in: endpoint))])
        }
        #expect(matches.count == expectedMethods.count && Set(actualMethods) == expectedMethods)
        #expect(endpoint.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(endpoint.contains("extension MerianNetworkClient"))
        #expect(endpoint.components(separatedBy: "performAuthenticatedJSONPost(").count == 9)
        for method in expectedMethods {
            #expect(!client.contains("func \(method)("))
        }
        for token in [
            "URLSession", "SupabaseManager", "Task {", "Task.detached", "static let shared",
            "performAuthenticatedRequest(", "endpointURL(", "JSONDecoder", "JSONSerialization", "catch"
        ] {
            #expect(!endpoint.contains(token), "Endpoint extensions must not own \(token)")
        }
        #expect(endpoint.range(of: #"(?m)^    (?:private )?(?:static )?(?:let|var)\s"#, options: .regularExpression) == nil)
        #expect(!endpoint.contains("func requestCommunityIdentification("))
        #expect(client.components(separatedBy: "    func requestCommunityIdentification(").count == 3)
    }

    @Test func exploreBrowsingStaysInItsEndpointOwner() throws {
        let root = try networkRoot()
        let endpoint = try String(
            contentsOf: root.appendingPathComponent("Endpoints/MerianNetworkClient+ExploreBrowsing.swift"),
            encoding: .utf8
        )
        let client = try String(contentsOf: root.appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8)
        let expectedMethods: Set<String> = [
            "getExploreFeed", "getExploreMapPoints", "getExplorePost", "getExplorePostDetail",
            "getExploreAuthorProfile", "getExploreAuthorPosts", "getExploreHashtagPosts", "getExploreSpeciesPosts"
        ]
        let declarations = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
        let matches = declarations.matches(in: endpoint, range: NSRange(endpoint.startIndex..., in: endpoint))
        let actualMethods = try matches.map { match in
            String(endpoint[try #require(Range(match.range(at: 1), in: endpoint))])
        }
        #expect(matches.count == expectedMethods.count && Set(actualMethods) == expectedMethods)
        #expect(endpoint.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(endpoint.contains("extension MerianNetworkClient"))
        #expect(endpoint.components(separatedBy: "performAuthenticatedJSONPost(").count == 9)
        for method in expectedMethods {
            #expect(!client.contains("func \(method)("))
        }
        for token in [
            "URLSession", "SupabaseManager", "Task {", "Task.detached", "static let shared",
            "performAuthenticatedRequest(", "endpointURL(", "JSONDecoder", "JSONSerialization", "catch"
        ] {
            #expect(!endpoint.contains(token), "Endpoint extensions must not own \(token)")
        }
        #expect(endpoint.range(of: #"(?m)^    (?:private )?(?:static )?(?:let|var)\s"#, options: .regularExpression) == nil)
        for method in [
            "shareScanToExplore", "requestCommunityIdentification", "performSpeciesDictionaryRequest"
        ] {
            #expect(client.contains("func \(method)("), "Keep non-browsing ownership unchanged: \(method)")
        }
    }

    @Test func exploreInteractionsStayInTheirEndpointOwner() throws {
        let root = try networkRoot()
        let endpoint = try String(
            contentsOf: root.appendingPathComponent("Endpoints/MerianNetworkClient+ExploreInteractions.swift"),
            encoding: .utf8
        )
        let client = try String(contentsOf: root.appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8)
        let expectedMethods: Set<String> = [
            "getExploreComments", "getExploreCommentReplies", "getExploreMentionSuggestions",
            "setExplorePostLike", "setUserFollow", "createExploreComment", "deleteExploreComment",
            "toggleExploreCommentReaction", "reportExploreComment", "reportExplorePost", "reportUser", "blockUser"
        ]
        let declarations = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
        let matches = declarations.matches(in: endpoint, range: NSRange(endpoint.startIndex..., in: endpoint))
        let actualMethods = try matches.map { match in
            String(endpoint[try #require(Range(match.range(at: 1), in: endpoint))])
        }
        #expect(matches.count == expectedMethods.count && Set(actualMethods) == expectedMethods)
        #expect(endpoint.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(endpoint.contains("extension MerianNetworkClient"))
        #expect(endpoint.components(separatedBy: "performAuthenticatedJSONPost(").count == 13)
        #expect(endpoint.components(separatedBy: "responseType:").count == 8)
        for method in expectedMethods {
            #expect(!client.contains("func \(method)("))
        }
        for token in [
            "URLSession", "SupabaseManager", "Task {", "Task.detached", "static let shared",
            "performAuthenticatedRequest(", "endpointURL(", "JSONDecoder", "JSONSerialization", "catch"
        ] {
            #expect(!endpoint.contains(token), "Endpoint extensions must not own \(token)")
        }
        #expect(endpoint.range(of: #"(?m)^    (?:private )?(?:static )?(?:let|var)\s"#, options: .regularExpression) == nil)
        for method in [
            "shareScanToExplore", "requestCommunityIdentification", "performSpeciesDictionaryRequest"
        ] {
            #expect(client.contains("func \(method)("), "Keep non-interaction ownership unchanged: \(method)")
        }
    }

    @Test func notificationsStayInTheirEndpointOwner() throws {
        try expectEndpointOwnership(
            filename: "MerianNetworkClient+Notifications.swift",
            methods: [
                "getExploreNotifications", "getUnreadExploreNotificationCount",
                "markExploreNotificationsRead", "registerPushDevice"
            ],
            typedResponseCount: 3
        )
    }

    @Test func publicProfileStaysInItsEndpointOwner() throws {
        try expectEndpointOwnership(
            filename: "MerianNetworkClient+PublicProfile.swift",
            methods: [
                "updatePublicUsername", "updatePublicDisplayName",
                "updatePublicAvatar", "checkPublicUsernameAvailability"
            ],
            typedResponseCount: 4
        )
    }

    @Test func explorePostManagementStaysInItsEndpointOwner() throws {
        try expectEndpointOwnership(
            filename: "MerianNetworkClient+ExplorePostManagement.swift",
            methods: [
                "getExploreComposerMedia", "getExploreShareState", "getExploreMediaIncidents",
                "unshareExplorePost", "updateExplorePostFieldNotes", "updateExplorePostContent"
            ],
            typedResponseCount: 5
        )
        let endpoint = try String(
            contentsOf: networkRoot().appendingPathComponent("Endpoints/MerianNetworkClient+ExplorePostManagement.swift"),
            encoding: .utf8
        )
        #expect(endpoint.components(separatedBy: "decodingFailure: .invalidResponse").count == 3)
        #expect(endpoint.components(separatedBy: "idempotencyKey: UUID().uuidString.lowercased()").count == 2)
        #expect(endpoint.contains("state.scanId.caseInsensitiveCompare(scanId) == .orderedSame"))
        #expect(endpoint.contains("DateUtilities.iso8601FractionalFormatter"))
    }

    private func expectEndpointOwnership(
        filename: String,
        methods: Set<String>,
        typedResponseCount: Int
    ) throws {
        let root = try networkRoot()
        let endpoint = try String(contentsOf: root.appendingPathComponent("Endpoints/\(filename)"), encoding: .utf8)
        let client = try String(contentsOf: root.appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8)
        let declarations = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
        let matches = declarations.matches(in: endpoint, range: NSRange(endpoint.startIndex..., in: endpoint))
        let actualMethods = try matches.map { match in
            String(endpoint[try #require(Range(match.range(at: 1), in: endpoint))])
        }
        #expect(matches.count == methods.count && Set(actualMethods) == methods)
        #expect(endpoint.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(endpoint.contains("extension MerianNetworkClient"))
        #expect(endpoint.components(separatedBy: "performAuthenticatedJSONPost(").count == methods.count + 1)
        #expect(endpoint.components(separatedBy: "responseType:").count == typedResponseCount + 1)
        for method in methods {
            #expect(!client.contains("func \(method)("))
        }
        for token in [
            "URLSession", "SupabaseManager", "Task {", "Task.detached", "static let shared",
            "performAuthenticatedRequest(", "endpointURL(", "JSONDecoder", "JSONSerialization", "catch"
        ] {
            #expect(!endpoint.contains(token), "Endpoint extensions must not own \(token)")
        }
        #expect(endpoint.range(of: #"(?m)^    (?:private )?(?:static )?(?:let|var)\s"#, options: .regularExpression) == nil)
        for method in ["shareScanToExplore", "requestCommunityIdentification", "generateUploadURLs", "performSpeciesDictionaryRequest"] {
            #expect(client.contains("func \(method)("), "Keep media, upload, and Dictionary ownership unchanged: \(method)")
        }
    }

    private func networkRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("project.yml").path) {
                return directory.appendingPathComponent("apps/ios/Merian/Core/Network")
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
