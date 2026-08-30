import SwiftUI

/// Abstracted component providing an isolated interface for queuing Darwin Core (DwC-A) exports.
/// Exports are packaged asynchronously via Supabase Edge Function webhooks and emailed to the user.
struct ExportScans: View {
    let supabase: SupabaseManager
    @Binding var isExporting: Bool
    @Binding var exportUrl: URL?
    var onExportRequested: (() -> Void)?

    @State private var viewModel = ExportScansViewModel()

    var body: some View {
        Section {
            if !supabase.isGuestUser {
                // Export Scans
                if viewModel.hasRequestedExport {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Export queued! We'll email you the download link when it's ready.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                } else if let url = exportUrl {
                    ShareLink(item: url) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Download scans (DwC-A)")
                        }
                    }
                } else {
                    Button(action: {
                        Task(priority: .userInitiated) {
                            let didRequest = await viewModel.requestExport()
                            if didRequest {
                                withAnimation {
                                    viewModel.presentSuccessfulRequest()
                                }
                                onExportRequested?()
                            }
                        }
                    }) {
                        HStack {
                            if viewModel.isRequesting {
                                ProgressView().padding(.trailing, 8)
                            }
                            Text("Export scans (DwC-A)")
                        }
                    }
                    .disabled(viewModel.isRequesting)
                }
            } else {
                Text("Sign in to export data")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        } header: {
            Text("Export Data")
        } footer: {
            Text("Darwin Core Archive (DwC-A) exports package your entire cloud collection into a standardized scientific format.")
        }
        .alert("Export Failed", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: viewModel.isRequesting, initial: true) { _, isRequesting in
            isExporting = isRequesting
        }
    }
}
