import SwiftUI

struct ShareImportView: View {
    @ObservedObject var viewModel: ShareImportViewModel

    var body: some View {
        VStack(spacing: 14) {
            switch viewModel.state {
            case .loading:
                compactStatus(icon: nil, title: "Preparing Image", showsProgress: true)
            case .ready:
                VStack(spacing: 14) {
                    preview
                    Text("Identify with Merian")
                        .font(.headline)
                    Button(action: viewModel.startUpload) {
                        Text("Identify")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .uploading:
                compactStatus(icon: nil, title: "Adding to Merian", showsProgress: true)
            case .success:
                compactStatus(icon: "checkmark.circle.fill", title: "Added to Merian", showsProgress: false)
            case .failure(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel", action: viewModel.cancelRequest)
                        .buttonStyle(.bordered)
                    Button("Retry", action: viewModel.retry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(18)
    }

    @ViewBuilder
    private var preview: some View {
        if let image = viewModel.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: "photo")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 112, height: 112)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func compactStatus(icon: String?, title: String, showsProgress: Bool) -> some View {
        HStack(spacing: 12) {
            if showsProgress {
                ProgressView()
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.green)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
