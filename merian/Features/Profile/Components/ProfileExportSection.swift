import SwiftUI

struct ProfileExportSection: View {
    let supabase: SupabaseManager
    @Binding var isExporting: Bool
    @Binding var exportUrl: URL?
    
    var body: some View {
        Section {
            if !supabase.isGuestUser {
                // Export Scans
                if let url = exportUrl {
                    ShareLink(item: url) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Download Scans (DwC-A)")
                        }
                    }
                } else {
                    Button(action: {
                        Task.detached(priority: .userInitiated) {
                            await MainActor.run { isExporting = true }
                            do {
                                let url = try await MerianNetworkClient.shared.exportDwcA(scope: "user")
                                await MainActor.run {
                                    self.exportUrl = url
                                    self.isExporting = false
                                }
                            } catch {
                                print("Export failed: \(error)")
                                await MainActor.run { isExporting = false }
                            }
                        }
                    }) {
                        HStack {
                            if isExporting {
                                ProgressView().padding(.trailing, 8)
                            }
                            Text("Export Scans (DwC-A)")
                        }
                    }
                    .disabled(isExporting)
                }
            } else {
                Text("Sign in with Apple to export data")
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
