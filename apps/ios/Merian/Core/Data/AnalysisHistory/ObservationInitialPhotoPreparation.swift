import Foundation

/// V9 geometry projection. Both artifact identities/hashes are bound by the
/// enclosing manifest digest. This is not a codec, file or funding authority.
struct ObservationInitialPhotoPreparation: Equatable, Sendable {
    let format: SharedMediaNativePreparationRecipe.Format
    let cropDisplaySize: Double?
    let quarterTurns: Int
    let scale: Double
    let offsetX: Double
    let offsetY: Double
    let cameraVerticalCenter: Double?
    let sourceSelection: NormalizedImageFocusRegion?

    /// A still with no crop is full-aspect preparation, not a centered square.
    var isFullFrame: Bool { format != .cameraStill && cropDisplaySize == nil }

    init(_ value: Any?) throws {
        let row = try ObservationHistoryPage.object(value, keys: ["schema_version", "coordinate_basis", "format",
            "crop_display_size", "quarter_turns", "scale", "offset_x", "offset_y", "camera_vertical_center", "source_selection"])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 1,
              row["coordinate_basis"] as? String == "upright_source_top_left_v1",
              let text = row["format"] as? String, let format = SharedMediaNativePreparationRecipe.Format(rawValue: text) else {
            throw ObservationHistoryError.invalidSnapshot
        }
        func number(_ value: Any?) throws -> Double {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else {
                throw ObservationHistoryError.invalidSnapshot
            }
            return n.doubleValue == 0 ? 0 : n.doubleValue
        }
        self.format = format
        cropDisplaySize = row["crop_display_size"] is NSNull ? nil : try number(row["crop_display_size"])
        quarterTurns = try ObservationHistoryPage.integer(row["quarter_turns"], maximum: 3)
        scale = try number(row["scale"])
        offsetX = try number(row["offset_x"])
        offsetY = try number(row["offset_y"])
        cameraVerticalCenter = row["camera_vertical_center"] is NSNull ? nil : try number(row["camera_vertical_center"])
        if row["source_selection"] is NSNull {
            sourceSelection = nil
        } else {
            let selection = try ObservationHistoryPage.object(row["source_selection"], keys: ["x", "y", "width", "height", "source"])
            sourceSelection = try JSONDecoder().decode(NormalizedImageFocusRegion.self,
                from: JSONSerialization.data(withJSONObject: selection))
        }
        // One geometry validator owns native format semantics. isPro is not
        // serialized and does not affect geometry validation or restore.
        do {
            try nativeRecipe.validate()
        } catch { throw ObservationHistoryError.invalidSnapshot }
    }

    init(recipe: SharedMediaNativePreparationRecipe) throws {
        try recipe.validate()
        format = recipe.format; cropDisplaySize = recipe.cropDisplaySize
        quarterTurns = recipe.quarterTurns; scale = recipe.scale
        offsetX = recipe.offsetX; offsetY = recipe.offsetY
        cameraVerticalCenter = recipe.cameraVerticalCenter; sourceSelection = recipe.sourceSelection
    }

    private var nativeRecipe: SharedMediaNativePreparationRecipe {
        .init(format: format, isPro: false, cropDisplaySize: cropDisplaySize,
              quarterTurns: quarterTurns, scale: scale, offsetX: offsetX, offsetY: offsetY,
              cameraVerticalCenter: cameraVerticalCenter, sourceSelection: sourceSelection)
    }

    var object: [String: Any] {
        ["schema_version": 1, "coordinate_basis": "upright_source_top_left_v1", "format": format.rawValue,
         "crop_display_size": cropDisplaySize.map { $0 as Any } ?? NSNull(),
         "quarter_turns": quarterTurns, "scale": scale, "offset_x": offsetX, "offset_y": offsetY,
         "camera_vertical_center": cameraVerticalCenter.map { $0 as Any } ?? NSNull(),
         "source_selection": sourceSelection.map { ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height,
             "source": "user_selection"] as [String: Any] as Any } ?? NSNull()]
    }

    var fingerprintFields: [String] {
        func binary64(_ value: Double) -> String { String(format: "%016llx", (value == 0 ? 0.0 : value).bitPattern) }
        var fields = ["1", "upright_source_top_left_v1", format.rawValue, cropDisplaySize == nil ? "0" : "1"]
        if let cropDisplaySize { fields.append(binary64(cropDisplaySize)) }
        fields += [String(quarterTurns), binary64(scale), binary64(offsetX), binary64(offsetY), cameraVerticalCenter == nil ? "0" : "1"]
        if let cameraVerticalCenter { fields.append(binary64(cameraVerticalCenter)) }
        fields.append(sourceSelection == nil ? "0" : "1")
        if let sourceSelection { fields += sourceSelection.fingerprintFields ?? [] }
        return fields
    }
}
