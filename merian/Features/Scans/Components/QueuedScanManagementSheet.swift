import SwiftUI

// MARK: - Queued Scan Management Sheet

/// Bottom sheet presented when a user taps a pending scan tile in the library grid.
///
/// Displays a thumbnail, per-scan status badge, live pipeline progress bar, and
/// capture metadata. Provides actions to cancel/delete the scan or dismiss.
struct QueuedScanManagementSheet: View {
    let queuedScan: OfflineQueuedScan
    let isOnline: Bool
    let onDelete: () -> Void
    let onClose: () -> Void

    @Environment(SyncStateManager.self) private var syncStateManager
    @State private var thumbnail: UIImage?

    private var statusIcon: String {
        guard isOnline else { return "wifi.slash" }
        switch queuedScan.queueState {
        case .pending:     return "arrow.up.circle"
        case .uploading:   return "arrow.up.circle.fill"
        case .staged:      return "cpu"
        case .inferencing: return "sparkles"
        case .failed:      return "exclamationmark.circle"
        }
    }

    private var statusText: String {
        guard isOnline else { return "Waiting for network connection" }
        switch queuedScan.queueState {
        case .pending:     return "Queued for upload"
        case .uploading:   return "Uploading image..."
        case .staged:      return "Preparing analysis..."
        case .inferencing: return "AI identifying subject..."
        case .failed:      return "Upload failed"
        }
    }

    private var isActivelyProcessing: Bool {
        isOnline && (queuedScan.queueState == .uploading || queuedScan.queueState == .inferencing)
    }

    /// Deterministic 0–1 progress fraction derived from the global pipeline phase.
    /// Maps upload → inference → finalize to visually distinct thirds so the user
    /// sees clear advancement even though we don't have per-byte progress.
    private var pipelineProgress: Double {
        switch syncStateManager.phase {
        case .idle:        return 0
        case .uploading:   return 0.35
        case .inferencing: return 0.70
        case .finalizing:  return 0.95
        }
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: queuedScan.timestamp, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Thumbnail Header
            ZStack(alignment: .bottom) {
                Group {
                    if let img = thumbnail {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
                .clipped()

                // Bottom gradient so status badge is always legible
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )

                // Status badge
                HStack(spacing: 6) {
                    if isActivelyProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // MARK: Metadata
            VStack(spacing: 4) {
                Text("Pending analysis")
                    .font(.title3)
                    .fontWeight(.bold)

                HStack(spacing: 14) {
                    Label(relativeTimestamp, systemImage: "clock")
                    if let location = queuedScan.locationName {
                        Label(location, systemImage: "location")
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            // MARK: Pipeline Progress
            // Shown when the global sync pipeline is actively running so the user
            // sees a live indicator of where their scan sits in the process.
            // pipelineProgress animates forward as the phase advances through
            // upload → inference → finalize without blocking UI on the main thread.
            if syncStateManager.phase != .idle {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: pipelineProgress)
                        .tint(.blue)
                        .animation(.easeInOut(duration: 0.6), value: pipelineProgress)

                    Text(syncStateManager.phase.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut, value: syncStateManager.phase.label)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            Spacer(minLength: 24)

            // MARK: Actions
            VStack(spacing: 10) {
                Button(role: .destructive, action: onDelete) {
                    Text("Cancel analysis & delete")
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(action: onClose) {
                    Text("Close")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.visible)
        .task(id: queuedScan.id) {
            thumbnail = nil
            guard let fileName = queuedScan.localImagePaths.first else { return }
            let url = URL.documentsDirectory.appendingPathComponent(fileName)
            // Downsample is CPU-heavy — run off the main actor so the pipeline's
            // await MainActor.run calls are not queued behind disk I/O.
            let cgImage = await Task.detached(priority: .userInitiated) {
                ImageDownsampler.shared.downsample(url: url, maxSize: 400)
            }.value
            guard let cgImage else { return }
            thumbnail = UIImage(cgImage: cgImage)
        }
    }
}
