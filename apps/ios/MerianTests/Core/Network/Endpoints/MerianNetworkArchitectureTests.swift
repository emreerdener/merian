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

        let encodedStart = try #require(client.range(of: "    func performAuthenticatedEncodedJSONPost<"))
        let encodedEnd = try #require(client.range(of: "\n    }", range: encodedStart.upperBound..<client.endIndex))
        let encodedBridge = String(client[encodedStart.lowerBound..<encodedEnd.upperBound])
        for token in [
            "Body: Encodable", "async throws -> Data", "try endpointURL(function)",
            "try JSONEncoder().encode(body)", "method: \"POST\"", "body: bodyData",
            "timeoutInterval: timeoutInterval", "idempotencyKey: idempotencyKey", "return data"
        ] {
            #expect(encodedBridge.contains(token))
        }
        #expect(encodedBridge.components(separatedBy: "performAuthenticatedRequest(").count == 2)
        let encoding = try #require(encodedBridge.range(of: "try JSONEncoder().encode(body)"))
        let encodedTransport = try #require(encodedBridge.range(of: "try await performAuthenticatedRequest("))
        #expect(encoding.upperBound < encodedTransport.lowerBound)
        for token in ["decode", "catch", "Task", "retry"] {
            #expect(!encodedBridge.contains(token), "Encoded-body transport must not add \(token)")
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
            "shareScanToExplore", "requestCommunityIdentification"
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
            "shareScanToExplore", "requestCommunityIdentification"
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

    @Test func fieldChatStaysInItsEndpointOwnerWithoutOwningTransportOrState() throws {
        let root = try networkRoot()
        let endpoint = try String(
            contentsOf: root.appendingPathComponent("Endpoints/MerianNetworkClient+FieldChat.swift"), encoding: .utf8
        )
        let client = try String(contentsOf: root.appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8)
        let methods: Set<String> = [
            "loadInsightChat", "sendInsightChatMessage", "deleteInsightChat", "submitInsightChatFeedback",
            "submitInsightChatFeatureFeedback", "summarizeInsightChatForFieldNotes", "suggestInsightChatPrompts",
            "loadExplorePostChat", "sendExplorePostChatMessage", "deleteExplorePostChat",
            "submitExplorePostChatFeedback", "suggestExplorePostChatPrompts",
            "loadSpeciesDictionaryChat", "sendSpeciesDictionaryChatMessage", "deleteSpeciesDictionaryChat",
            "submitSpeciesDictionaryChatFeedback", "suggestSpeciesDictionaryChatPrompts"
        ]
        let declarations = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
        let matches = declarations.matches(in: endpoint, range: NSRange(endpoint.startIndex..., in: endpoint))
        let actualMethods = try matches.map { match in
            String(endpoint[try #require(Range(match.range(at: 1), in: endpoint))])
        }
        #expect(matches.count == 17 && Set(actualMethods) == methods)
        #expect(endpoint.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(endpoint.contains("extension MerianNetworkClient"))
        #expect(endpoint.components(separatedBy: "performAuthenticatedEncodedJSONPost(").count == 4)
        for method in methods { #expect(!client.contains("func \(method)(")) }
        for helper in [
            "insightChat", "performInsightChatRequest", "performExplorePostChat", "performExplorePostChatRequest",
            "performSpeciesDictionaryChat", "performSpeciesDictionaryChatRequest"
        ] {
            #expect(endpoint.contains("private func \(helper)("))
            #expect(!client.contains("func \(helper)("))
        }
        for token in [
            "URLSession", "SupabaseManager", "Task {", "Task.detached", "static let shared", "@MainActor",
            "performAuthenticatedRequest(", "endpointURL(", "JSONDecoder", "JSONEncoder", "JSONSerialization", "catch"
        ] {
            #expect(!endpoint.contains(token), "Field Chat endpoints must not own \(token)")
        }
        #expect(endpoint.range(of: #"(?m)^    (?:private )?(?:static )?(?:let|var)\s"#, options: .regularExpression) == nil)
        for method in [
            "ensureCloudScanAvailableForFieldChat", "shareScanToExplore", "requestCommunityIdentification"
        ] {
            #expect(client.contains("func \(method)("), "Preserve existing recovery and non-chat ownership: \(method)")
        }
        let storage = try String(contentsOf: root.appendingPathComponent("Endpoints/MerianNetworkClient+MediaStorage.swift"), encoding: .utf8)
        #expect(storage.contains("func generateUploadURLs(") && !client.contains("func generateUploadURLs("))
    }

    @Test func fieldChatValidationHasOneStatelessOwner() throws {
        let root = try networkRoot()
        let decoder = try String(
            contentsOf: root.appendingPathComponent("Decoding/FieldChatResponseDecoder.swift"), encoding: .utf8
        )
        let client = try String(contentsOf: root.appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8)
        #expect(decoder.contains("enum FieldChatResponseDecoder"))
        #expect(decoder.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        for method in ["decodeConversation", "decodeFeedback", "decodeFeatureFeedback", "decodeSummary", "decodePromptSuggestions"] {
            #expect(decoder.contains("static func \(method)("))
        }
        for name in ["promptCategoryAllowlist", "unsafePromptPatterns", "internalUUIDPattern", "maxResponseBytes", "maxMessageCharacters"] {
            #expect(decoder.contains("private static let \(name)"))
        }
        #expect(decoder.contains("private static func makeDecoder()"))
        #expect(decoder.contains("private static func validateResponseSize("))
        for token in ["URLSession", "Supabase", "Task", "@MainActor", "static var", "MerianNetworkClient"] {
            #expect(!decoder.contains(token), "The Field Chat decoder must not own \(token)")
        }
        for token in ["decodeInsightChatResponse", "makeInsightChatDecoder", "maxFieldChatResponseBytes", "unsafeInsightChatPromptPatterns"] {
            #expect(!client.contains(token), "Field Chat-only validation must not remain in the client: \(token)")
        }
    }

    @Test func speciesDictionaryEndpointsOwnMappingWithoutTransportOrMutableState() throws {
        let root = try networkRoot()
        let endpoint = try String(
            contentsOf: root.appendingPathComponent("Endpoints/MerianNetworkClient+SpeciesDictionary.swift"), encoding: .utf8
        )
        let client = try String(contentsOf: root.appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8)
        let methods = ["getSpeciesDictionary", "getSpeciesDictionaryCatalog", "getSpeciesDictionaryOverview", "getSpeciesObservationStats"]
        let declarations = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
        let matches = declarations.matches(in: endpoint, range: NSRange(endpoint.startIndex..., in: endpoint))
        let actualMethods = try matches.map { String(endpoint[try #require(Range($0.range(at: 1), in: endpoint))]) }
        #expect(matches.count == 6 && Set(actualMethods) == Set(methods))
        #expect(actualMethods.filter { $0 == "getSpeciesDictionary" }.count == 2)
        #expect(actualMethods.filter { $0 == "getSpeciesDictionaryCatalog" }.count == 2)
        #expect(endpoint.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(endpoint.contains("private func performSpeciesDictionaryRequest("))
        #expect(endpoint.components(separatedBy: "performAuthenticatedJSONPost(").count == 3)
        #expect(endpoint.components(separatedBy: "performCachedSpeciesDictionaryRequest(").count == 2)
        #expect(endpoint.components(separatedBy: "performCachedSpeciesObservationStatsRequest(").count == 2)
        #expect(endpoint.components(separatedBy: "validateEndpointConfiguration(").count == 5)
        for method in methods + ["performSpeciesDictionaryRequest"] { #expect(!client.contains("func \(method)(")) }
        for token in [
            "URLSession", "Supabase", "Task", "static let shared", "NSLock", "JSONDecoder",
            "JSONSerialization", "performAuthenticatedRequest(", "performAuthenticatedJSONGet(", "endpointURL(",
            "speciesDictionaryResponses", "SpeciesDictionaryResponseCache", "catch"
        ] {
            #expect(!endpoint.contains(token), "Dictionary endpoint must not own \(token)")
        }
        #expect(endpoint.range(of: #"(?m)^    (?:private )?(?:static )?(?:let|var)\s"#, options: .regularExpression) == nil)

        for (method, configuration, cacheBridge) in [
            ("func getSpeciesObservationStats(", "species-observation-stats", "performCachedSpeciesObservationStatsRequest("),
            ("private func performSpeciesDictionaryRequest(", "species-dictionary", "performCachedSpeciesDictionaryRequest(")
        ] {
            let start = try #require(endpoint.range(of: method))
            let end = try #require(endpoint.range(of: "\n    }", range: start.upperBound..<endpoint.endIndex))
            let body = String(endpoint[start.lowerBound..<end.upperBound])
            let configured = try #require(body.range(of: #"try validateEndpointConfiguration("\#(configuration)")"#))
            let identity = try #require(body.range(of: "SpeciesDictionaryIdentity"))
            let dispatch = try #require(body.range(of: cacheBridge))
            #expect(configured.upperBound < identity.lowerBound && identity.upperBound < dispatch.lowerBound)
        }
    }

    @Test func speciesDictionaryCachesAndValidationHaveContainedOwners() throws {
        let root = try networkRoot()
        let cache = try String(
            contentsOf: root.appendingPathComponent("Caching/SpeciesDictionaryResponseCache.swift"), encoding: .utf8
        )
        let validator = try String(
            contentsOf: root.appendingPathComponent("Decoding/SpeciesDictionaryResponseValidator.swift"), encoding: .utf8
        )
        let client = try String(contentsOf: root.appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8)
        for token in [
            "private let dictionary:", "private let observationStats:", "private final class SpeciesResponseMemo<Value>",
            "private let lock = NSLock()", "private var entries:", "now: @escaping () -> Date = Date.init",
            "timeToLive: 10 * 60, limit: 64", "timeToLive: 5 * 60, limit: 64"
        ] { #expect(cache.contains(token), "Cache encapsulation or policy changed: \(token)") }
        #expect(client.contains("private let speciesDictionaryResponses = SpeciesDictionaryResponseCache()"))
        #expect(client.contains("speciesDictionaryResponses.resetForTesting()"))
        #expect(client.contains("didSet { resetSpeciesDictionaryCacheForTesting() }"))
        for token in ["speciesDictionaryCacheLock", "speciesObservationStatsCacheLock", "SpeciesDictionaryCacheEntry"] {
            #expect(!client.contains(token), "Raw Dictionary cache state must not remain in the client")
        }
        #expect(validator.contains("enum SpeciesDictionaryResponseValidator"))
        #expect(validator.contains("private static func isValidDictionaryEntry("))
        for method in ["catalog", "overview", "dictionaryEntry", "observationStats"] {
            #expect(validator.contains("static func \(method)("))
        }
        for source in [cache, validator] {
            #expect(source.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
            for token in ["static let shared", "static var", "URLSession", "Supabase", "MerianNetworkClient", "Task", "@MainActor"] {
                #expect(!source.contains(token), "Dictionary response owners must not own \(token)")
            }
        }
        #expect(!validator.contains("JSONDecoder") && !validator.contains("catch"))
    }

    @Test func speciesDictionaryCacheAccessRequiresFixedValidatedRequests() throws {
        let client = try String(
            contentsOf: networkRoot().appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8
        )
        for (method, function, response, result, read, validation, write) in [
            ("performCachedSpeciesDictionaryRequest", "species-dictionary", "SpeciesDictionaryResponse", "SpeciesDictionaryEntry",
             "dictionaryEntry", "dictionaryEntry", "storeDictionaryEntry"),
            ("performCachedSpeciesObservationStatsRequest", "species-observation-stats", "SpeciesObservationStatsResponse",
             "SpeciesObservationStatsEntry", "observationStatsEntry", "observationStats", "storeObservationStatsEntry")
        ] {
            let start = try #require(client.range(of: "    func \(method)("))
            let end = try #require(client.range(of: "\n    }", range: start.upperBound..<client.endIndex))
            let bridge = String(client[start.lowerBound..<end.upperBound])
            let bodyStart = try #require(bridge.firstIndex(of: "{"))
            let signature = String(bridge[..<bodyStart])
            #expect(signature.contains("async throws -> \(result)"))
            for token in ["@escaping", "loader", "response:", "responseType:", "cache:", "insert", "<"] {
                #expect(!signature.contains(token), "Cache bridge must not accept a validation bypass: \(token)")
            }
            #expect(bridge.contains(#"function: "\#(function)""#))
            #expect(bridge.contains("responseType: \(response).self"))
            let lookup = try #require(bridge.range(of: "speciesDictionaryResponses.\(read)("))
            let hit = try #require(bridge.range(of: "return cached"))
            let transport = try #require(bridge.range(of: "try await performAuthenticatedJSON"))
            let validated = try #require(bridge.range(of: "try SpeciesDictionaryResponseValidator.\(validation)("))
            let inserted = try #require(bridge.range(of: "speciesDictionaryResponses.\(write)("))
            #expect(lookup.upperBound < hit.lowerBound && hit.upperBound < transport.lowerBound)
            #expect(transport.upperBound < validated.lowerBound && validated.upperBound < inserted.lowerBound)
            for token in ["Task", "catch", "URLSession", "Supabase", "onSuccess", "@escaping"] {
                #expect(!bridge.contains(token), "Cache bridge must not add \(token)")
            }
        }
        #expect(client.components(separatedBy: "speciesDictionaryResponses.").count == 6)
        #expect(!client.contains("-> SpeciesDictionaryResponseCache"))
    }

    @Test func typedGETAndConfigurationGuardReusePrivateTransportWithoutNewPolicy() throws {
        let client = try String(
            contentsOf: networkRoot().appendingPathComponent("MerianNetworkClient.swift"), encoding: .utf8
        )
        let start = try #require(client.range(of: "    private func performAuthenticatedJSONGet<"))
        let end = try #require(client.range(of: "\n    }", range: start.upperBound..<client.endIndex))
        let bridge = String(client[start.lowerBound..<end.upperBound])
        for token in [
            "try endpointURL(function)", "components?.queryItems = queryItems", "throw MerianError.invalidURL",
            "method: \"GET\"", "timeoutInterval: timeoutInterval", "makeExploreDecoder().decode(responseType, from: data)"
        ] { #expect(bridge.contains(token)) }
        #expect(bridge.components(separatedBy: "performAuthenticatedRequest(").count == 2)
        for token in ["catch", "Task", "retry", "performPublicGETRequest", "body:", "idempotencyKey:"] {
            #expect(!bridge.contains(token), "GET bridge must not add \(token)")
        }
        let guardStart = try #require(client.range(of: "    func validateEndpointConfiguration("))
        let guardEnd = try #require(client.range(of: "\n    }", range: guardStart.upperBound..<client.endIndex))
        let guardBody = String(client[guardStart.lowerBound..<guardEnd.upperBound])
        #expect(guardBody.contains("_ = try endpointURL(function)"))
        #expect(!guardBody.contains("Task") && !guardBody.contains("async") && !guardBody.contains("->"))
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
        for method in ["shareScanToExplore", "requestCommunityIdentification"] {
            #expect(client.contains("func \(method)("), "Keep publication and recovery ownership unchanged: \(method)")
        }
        let storage = try String(contentsOf: root.appendingPathComponent("Endpoints/MerianNetworkClient+MediaStorage.swift"), encoding: .utf8)
        #expect(storage.contains("func generateUploadURLs(") && !client.contains("func generateUploadURLs("))
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
