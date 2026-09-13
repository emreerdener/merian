enum FieldTripCommunityMode: String, CaseIterable, Identifiable {
    case smart
    case following
    case recent

    var id: String { rawValue }
}
