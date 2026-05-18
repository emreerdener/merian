import SwiftUI

struct ShareImportView: View {
    @ObservedObject var viewModel: ShareImportViewModel

    var body: some View {
        VStack(spacing: 18) {
            preview

            switch viewModel.state {
            case .loading:
                ProgressView()
                Text("Preparing Image")
                    .font(.headline)
            case .ready:
                Text("Identify with Merian")
                    .font(.headline)
                Button(action: viewModel.startUpload) {
                    Text("Identify")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            case .uploading:
                ProgressView()
                Text("Uploading to Merian")
                    .font(.headline)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Queued for Identification")
                    .font(.headline)
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
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
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
}
