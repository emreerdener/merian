import SwiftUI

struct ShareButton: View {
    let shareExternally: () -> Void
    let onShareToExplore: (() -> Void)?
    let isSharingToExplore: Bool
    var sharedExplorePostId: String?
    var onViewInExplore: (() -> Void)?
    
    @State private var showingOptions = false
    
    var body: some View {
        Button(action: {
            if onShareToExplore != nil || onViewInExplore != nil {
                showingOptions = true
            } else {
                shareExternally()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                Text("Share")
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .sheet(isPresented: $showingOptions) {
            VStack(spacing: 24) {
                Text("Share Options")
                    .font(.headline)
                    .padding(.top, 8)
                
                VStack(spacing: 12) {
                    if sharedExplorePostId != nil, let onViewInExplore {
                        Button {
                            showingOptions = false
                            onViewInExplore()
                        } label: {
                            Label("View in Explore", systemImage: "safari")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.blue)
                    } else if let onShareToExplore {
                        Button {
                            showingOptions = false
                            onShareToExplore()
                        } label: {
                            Label(isSharingToExplore ? "Sharing to Explore..." : "Share to Explore", systemImage: "safari")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.blue)
                        .disabled(isSharingToExplore)
                    }

                    Button {
                        showingOptions = false
                        shareExternally()
                    } label: {
                        Label("Share via Messages, Mail, etc.", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.primary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .presentationDetents([.height(240)])
            .presentationDragIndicator(.visible)
        }
    }
}
