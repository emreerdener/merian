import Foundation

// MARK: - Inference Generation

enum InferenceGenerationMetadataContract {
    static func json(for generation: UUID) -> String {
        #"{"inference_generation":""# +
            generation.uuidString.lowercased() +
            #""}"#
    }

    static func generation(in metadataJSON: String?) -> UUID? {
        guard let value = OfflineScanJobMetadataContract.object(
            from: metadataJSON
        )["inference_generation"] as? String else {
            return nil
        }
        return UUID(uuidString: value)
    }

    static func matches(_ generation: UUID, in metadataJSON: String?) -> Bool {
        self.generation(in: metadataJSON) == generation
    }

    static func setting(
        _ generation: UUID,
        in metadataJSON: String?
    ) -> String {
        var object = OfflineScanJobMetadataContract.object(from: metadataJSON)
        object["inference_generation"] = generation.uuidString.lowercased()
        return OfflineScanJobMetadataContract.json(from: object) ?? json(
            for: generation
        )
    }

    /// Removes only the generation property and preserves funding and any
    /// future metadata fields. Returns nil when no properties remain.
    static func removing(
        _ generation: UUID,
        from metadataJSON: String?
    ) -> String? {
        var object = OfflineScanJobMetadataContract.object(from: metadataJSON)
        guard let value = object["inference_generation"] as? String,
              UUID(uuidString: value) == generation else {
            return metadataJSON
        }
        object.removeValue(forKey: "inference_generation")
        return OfflineScanJobMetadataContract.json(from: object)
    }
}

// MARK: - Offline Job Metadata

enum OfflineScanJobMetadataContract {
    private static let fundingReservationKey = "funding_reservation"
    private static let fundingReleasedKey = "funding_reservation_released"
    private static let backgroundAccountWorkKey = "background_account_work"

    static func object(from metadataJSON: String?) -> [String: Any] {
        guard let metadataJSON,
              let data = metadataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    static func json(from object: [String: Any]) -> String? {
        guard !object.isEmpty,
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func funding(in metadataJSON: String?) -> ScanFundingReservation? {
        let object = object(from: metadataJSON)
        guard let rawFunding = object[fundingReservationKey],
              JSONSerialization.isValidJSONObject(rawFunding),
              let data = try? JSONSerialization.data(withJSONObject: rawFunding),
              let funding = try? JSONDecoder().decode(
                  ScanFundingReservation.self,
                  from: data
              ),
              !funding.scanId.isEmpty else {
            return nil
        }
        return funding
    }

    static func settingFunding(
        _ funding: ScanFundingReservation,
        in metadataJSON: String?
    ) -> String? {
        var object = object(from: metadataJSON)
        guard let data = try? JSONEncoder().encode(funding),
              let rawFunding = try? JSONSerialization.jsonObject(with: data) else {
            return metadataJSON
        }
        object[fundingReservationKey] = rawFunding
        object.removeValue(forKey: fundingReleasedKey)
        return json(from: object)
    }

    static func fundingWasReleased(in metadataJSON: String?) -> Bool {
        object(from: metadataJSON)[fundingReleasedKey] as? Bool == true
    }

    /// Persists proof that no provider dispatch occurred. The marker prevents a
    /// pre-protocol-3 job with no funding payload from being restored as an
    /// unknown complimentary blocker after relaunch.
    static func markingFundingReleased(in metadataJSON: String?) -> String? {
        var object = object(from: metadataJSON)
        object.removeValue(forKey: fundingReservationKey)
        object[fundingReleasedKey] = true
        return json(from: object)
    }

    static func backgroundAccountWork(
        in metadataJSON: String?
    ) -> BackgroundAccountWorkOwnership? {
        let object = object(from: metadataJSON)
        guard let rawValue = object[backgroundAccountWorkKey],
              JSONSerialization.isValidJSONObject(rawValue),
              let data = try? JSONSerialization.data(withJSONObject: rawValue)
        else {
            return nil
        }
        return try? JSONDecoder().decode(
            BackgroundAccountWorkOwnership.self,
            from: data
        )
    }

    static func settingBackgroundAccountWork(
        _ ownership: BackgroundAccountWorkOwnership,
        in metadataJSON: String?
    ) -> String? {
        var object = object(from: metadataJSON)
        guard let data = try? JSONEncoder().encode(ownership),
              let rawValue = try? JSONSerialization.jsonObject(with: data)
        else {
            return metadataJSON
        }
        object[backgroundAccountWorkKey] = rawValue
        return json(from: object)
    }

    static func clearingBackgroundAccountWork(
        in metadataJSON: String?
    ) -> String? {
        var object = object(from: metadataJSON)
        object.removeValue(forKey: backgroundAccountWorkKey)
        return json(from: object)
    }

    static func json(
        generation: UUID?,
        funding: ScanFundingReservation
    ) -> String? {
        var metadata = settingFunding(funding, in: nil)
        if let generation {
            metadata = InferenceGenerationMetadataContract.setting(
                generation,
                in: metadata
            )
        }
        return metadata
    }
}
