struct GeoprivacyOption: Identifiable, Equatable {
    let id: String
    let title: String
    let descriptor: String

    static let all = [
        GeoprivacyOption(
            id: "open",
            title: "Open",
            descriptor: "Your exact GPS coordinates are recorded and attached to each scan."
        ),
        GeoprivacyOption(
            id: "obscured",
            title: "Obscured",
            descriptor: "Coordinates are rounded to approximately a 10 km area, preserving regional context without exposing your precise location."
        ),
        GeoprivacyOption(
            id: "private",
            title: "Private",
            descriptor: "No location data is attached to your scans — your whereabouts remain entirely hidden."
        )
    ]
}
