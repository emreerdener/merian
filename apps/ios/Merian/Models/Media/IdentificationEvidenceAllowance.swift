/// Shared product allowance; media routing remains responsible for video provenance.
enum IdentificationEvidenceAllowance {
    static func permitsFreeScan(images: Int, audio: Int, descriptions: Int, videos: Int) -> Bool {
        guard images >= 0, audio >= 0, descriptions >= 0, videos == 0 else { return false }
        let physical = images + audio
        return (physical == 1 && descriptions <= 1) || (physical == 0 && descriptions == 1)
    }
}
