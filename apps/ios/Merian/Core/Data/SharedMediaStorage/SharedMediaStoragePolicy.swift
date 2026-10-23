import Foundation

/// Accounting only: this grants neither file access nor admission to inference.
enum SharedMediaStoragePolicy {
    static let pageSize = 128
    static let maximumTokenBytes = 1_024
    static let reserve: Int64 = 256 * PhotoPreparationPolicy.mib

    static func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard lhs >= 0, rhs >= 0, !overflow else { throw SharedMediaStorageFailure.invalid }
        return value
    }

    static func token(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= maximumTokenBytes,
              value != ".", value != "..", !value.contains("/"), !value.contains("\\"),
              !value.contains("\0") else { throw SharedMediaStorageFailure.invalid }
    }

    struct Totals: Equatable {
        private var packages: [UUID: Int64] = [:]
        private var pools: [SharedMediaStoragePool: Int64] = [:]
        private var outstanding: Int64 = 0
        private var exclusivePackages: [SharedMediaStoragePool: UUID] = [:]

        mutating func include(_ charge: SharedMediaStorageCharge) throws {
            let bytes = try SharedMediaStoragePolicy.add(charge.materialized, charge.reserved)
            if charge.pool == .observed {
                guard charge.reserved == 0, charge.packageID == nil else { throw SharedMediaStorageFailure.invalid }
                return // Occupied bytes already reduce the filesystem's available space.
            }
            guard let package = charge.packageID else { throw SharedMediaStorageFailure.invalid }
            try includeBudget(package: package, pool: charge.pool, bytes: bytes, unmaterialized: charge.reserved)
        }

        /// Logical overlap (P1 acquisition and metadata), not a second file or reservation.
        mutating func includeLogical(package: UUID, pool: SharedMediaStoragePool, bytes: Int64) throws {
            guard pool == .durable || pool == .acquisition else { throw SharedMediaStorageFailure.invalid }
            try includeBudget(package: package, pool: pool, bytes: bytes, unmaterialized: 0)
        }

        private mutating func includeBudget(package: UUID, pool: SharedMediaStoragePool, bytes: Int64, unmaterialized: Int64) throws {
            guard bytes >= 0, unmaterialized >= 0 else { throw SharedMediaStorageFailure.invalid }
            if pool == .preparation || pool == .transfer {
                guard exclusivePackages[pool].map({ $0 == package }) ?? true else { throw SharedMediaStorageFailure.capacity }
                exclusivePackages[pool] = package
            }
            outstanding = try SharedMediaStoragePolicy.add(outstanding, unmaterialized)
            pools[pool] = try SharedMediaStoragePolicy.add(pools[pool, default: 0], bytes)
            // Temporary copies belong to a package but are outside its durable envelope.
            packages[package] = try SharedMediaStoragePolicy.add(packages[package, default: 0], pool == .durable ? bytes : 0)
            guard packages.count <= PhotoPreparationPolicy.maximumPackages,
                  packages[package, default: 0] <= PhotoPreparationPolicy.package,
                  pools[.durable, default: 0] <= PhotoPreparationPolicy.durable,
                  pools[.acquisition, default: 0] <= 96 * PhotoPreparationPolicy.mib,
                  pools[.preparation, default: 0] <= 64 * PhotoPreparationPolicy.mib,
                  pools[.transfer, default: 0] <= 32 * PhotoPreparationPolicy.mib else {
                throw SharedMediaStorageFailure.capacity
            }
            let temporary = try SharedMediaStoragePolicy.add(
                SharedMediaStoragePolicy.add(pools[.acquisition, default: 0], pools[.preparation, default: 0]),
                pools[.transfer, default: 0])
            guard temporary <= PhotoPreparationPolicy.temporary else { throw SharedMediaStorageFailure.capacity }
        }

        /// Preparation overlap charges the existing temporary pool only; its
        /// reservation has already been counted once by physical ownership.
        mutating func includePhotoPreparation(package: UUID, bytes: Int64) throws {
            try includeBudget(package: package, pool: .preparation, bytes: bytes, unmaterialized: 0)
        }

        /// Photo references charge each package logically, while shared bytes
        /// and each envelope are charged only once to physical durable storage.
        mutating func includePhotoPhysical(materialized: Int64, reserved: Int64) throws {
            let bytes = try SharedMediaStoragePolicy.add(materialized, reserved)
            outstanding = try SharedMediaStoragePolicy.add(outstanding, reserved)
            pools[.durable] = try SharedMediaStoragePolicy.add(pools[.durable, default: 0], bytes)
            guard pools[.durable, default: 0] <= PhotoPreparationPolicy.durable else { throw SharedMediaStorageFailure.capacity }
        }

        mutating func includePhotoPackage(id: UUID, bytes: Int64) throws {
            guard bytes >= 0, packages[id] == nil, bytes <= PhotoPreparationPolicy.package else { throw SharedMediaStorageFailure.capacity }
            packages[id] = bytes
            guard packages.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
        }

        /// Accountless source bytes and reserved copy headroom are temporary,
        /// not synthetic packages. Occupied bytes already reduce free space.
        mutating func includeInboxAcquisition(bytes: Int64, unmaterialized: Int64) throws {
            guard bytes >= 0, unmaterialized >= 0 else { throw SharedMediaStorageFailure.invalid }
            pools[.acquisition] = try SharedMediaStoragePolicy.add(pools[.acquisition, default: 0], bytes)
            outstanding = try SharedMediaStoragePolicy.add(outstanding, unmaterialized)
            guard pools[.acquisition, default: 0] <= 96 * PhotoPreparationPolicy.mib,
                  try SharedMediaStoragePolicy.add(SharedMediaStoragePolicy.add(pools[.acquisition, default: 0],
                    pools[.preparation, default: 0]), pools[.transfer, default: 0]) <= PhotoPreparationPolicy.temporary else {
                throw SharedMediaStorageFailure.capacity
            }
        }

        func checkAvailable(_ available: Int64, additionalReservation: Int64 = 0) throws {
            guard available >= 0, available >= (try SharedMediaStoragePolicy.add(SharedMediaStoragePolicy.add(outstanding, SharedMediaStoragePolicy.reserve), additionalReservation)) else {
                throw SharedMediaStorageFailure.capacity
            }
        }
    }
}
