import SwiftUI

/// Abstracted component providing an isolated pipeline for packaging local JSON and Cloudflare bytes
/// synchronously into standardized Darwin Core zip folders.
struct ExportScans: View {
    let supabase: SupabaseManager
    @Binding var isExporting: Bool
    @Binding var exportUrl: URL?
    @State private var hasRequestedExport = false
    
    var body: some View {
        Section {
            if !supabase.isGuestUser {
                // Export Scans
                if hasRequestedExport {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Exporting... We'll notify you when ready.")
                            .font(.subheadline)
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
                            } catch {
                                print("🚨 Export architecture failed: \(error)")
                                await MainActor.run { isExporting = false }
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
    }
}
