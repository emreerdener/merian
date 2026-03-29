import SwiftUI

/// Abstracted component providing an isolated interface for queuing Darwin Core (DwC-A) exports.
/// Exports are packaged asynchronously via Supabase Edge Function webhooks and emailed to the user.
struct ExportScans: View {
    let supabase: SupabaseManager
    @Binding var isExporting: Bool
    @Binding var exportUrl: URL?
    @State private var hasRequestedExport = false
    @State private var errorMessage: String?
    
    var body: some View {
        Section {
            if !supabase.isGuestUser {
                // Export Scans
                if hasRequestedExport {
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
                        Task.detached(priority: .userInitiated) {
                            await MainActor.run { isExporting = true }
                            do {
                                // Maps request completely off timeout logic!
                                try await MerianNetworkClient.shared.requestDwcAExport(scope: "user")
                                await MainActor.run {
                                    self.isExporting = false
                                    withAnimation { self.hasRequestedExport = true }
                                }
                            } catch let error as MerianError {
                                await MainActor.run { 
                                    isExporting = false 
                                    if case .httpError(let statusCode, _) = error, statusCode == 429 {
                                        self.errorMessage = "You can only generate one Darwin Core Archive every 24 hours. Your most recent export was already emailed to you."
                                    } else {
                                        self.errorMessage = "Failed to queue export. Please try again later."
                                    }
                                }
                            } catch {
                                MerianLog.network.error("DwC-A export request failed: \(error, privacy: .private)")
                                await MainActor.run { 
                                    isExporting = false 
                                    self.errorMessage = "An unexpected error occurred."
                                }
                            }
                        }
                    }) {
                        HStack {
                            if isExporting {
                                ProgressView().padding(.trailing, 8)
                            }
                            Text("Export scans (DwC-A)")
                        }
                    }
                    .disabled(isExporting)
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
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
}
