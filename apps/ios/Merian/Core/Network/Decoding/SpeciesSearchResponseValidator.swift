import Foundation

enum SpeciesSearchResponseValidator {
    static func decode(_ data: Data, request: SpeciesSearchRequest) throws -> SpeciesSearchResponse {
        guard data.count <= 1_048_576 else { throw MerianError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response: SpeciesSearchResponse
        do {
            response = try decoder.decode(SpeciesSearchResponse.self, from: data)
        } catch {
            throw MerianError.invalidResponse
        }
        guard response.schemaVersion == 1, response.requestId == request.requestId,
              response.resultKind == request.resultKind, response.message.count <= 300,
              response.species.count <= 20, response.sightings.count <= 20,
              Set(response.species.map(\.id)).count == response.species.count,
              Set(response.sightings.map(\.id)).count == response.sightings.count,
              response.species.allSatisfy({ UUID(uuidString: $0.id) != nil && !$0.item.scientificName.isEmpty && !$0.item.commonName.isEmpty && $0.excerpt.count <= 300 }),
              response.sightings.allSatisfy({ UUID(uuidString: $0.id) != nil && UUID(uuidString: $0.scanId) != nil && $0.sharedAtDate != nil }),
              request.resultKind == .species ? response.sightings.isEmpty : response.species.isEmpty
        else { throw MerianError.invalidResponse }
        if let context = response.context {
            guard context.query.count <= 240, !context.query.isEmpty || context.group != nil else {
                throw MerianError.invalidResponse
            }
        }
        if response.status == .results {
            guard response.context != nil,
                  request.question != nil || response.context == request.context else { throw MerianError.invalidResponse }
        } else {
            guard response.species.isEmpty, response.sightings.isEmpty, response.nextCursor == nil,
                  response.status != .clarification || response.context != nil,
                  response.status == .clarification || response.context == request.context, !response.message.isEmpty else { throw MerianError.invalidResponse }
        }
        if let cursor = response.nextCursor {
            guard UUID(uuidString: cursor.id) != nil, cursor != request.cursor else { throw MerianError.invalidResponse }
            switch request.resultKind {
            case .species:
                guard cursor.id == response.species.last?.id, let rank = cursor.rank, rank.isFinite,
                      (0...10).contains(rank), cursor.sharedAt == nil else { throw MerianError.invalidResponse }
            case .sightings:
                guard cursor.id == response.sightings.last?.id, cursor.sharedAt == response.sightings.last?.sharedAt,
                      cursor.rank == nil else { throw MerianError.invalidResponse }
            }
        }
        return response
    }
}
