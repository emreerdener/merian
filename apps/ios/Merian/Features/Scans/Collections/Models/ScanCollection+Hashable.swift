extension ScanCollection: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (
        lhs: ScanCollection,
        rhs: ScanCollection
    ) -> Bool {
        lhs.id == rhs.id
    }
}
