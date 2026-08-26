import SwiftUI

struct ExploreCommunityIdentificationDetailView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: CommunityIdentificationDetailViewModel
    @State private var isSearchPresented = false
    @State private var isEditPresented = false
    @State private var pendingResolver: CommunityDisagreementResolverContext?

    init(requestId: String) {
        _viewModel = State(
            initialValue: CommunityIdentificationDetailViewModel(requestId: requestId)
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if viewModel.isLoading && viewModel.detail == nil {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
            } else if let errorMessage = viewModel.errorMessage,
                      viewModel.detail == nil {
                ExploreUnavailableStateView(
                    title: "Request unavailable",
                    message: errorMessage
                ) {
                    Task { await viewModel.load() }
                }
            } else if let detail = viewModel.detail {
                detailContent(detail)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let detail = viewModel.detail {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if viewModel.isOwnedByCurrentUser(detail) {
                            Button {
                                isEditPresented = true
                            } label: {
                                Label("Edit request", systemImage: "square.and.pencil")
                            }
                        } else {
                            Button(role: .destructive) {
                                Task { await viewModel.report(detail) }
                            } label: {
                                Label("Report post", systemImage: "flag")
                            }
                            .disabled(viewModel.isReporting)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .imageOverlayToolbarIconChrome(
                                isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground,
                                foregroundColor: .primary
                            )
                    }
                    .accessibilityLabel("Post options")
                    .imageOverlayToolbarButtonChrome(
                        isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
                    )
                }
            }
        }
        .merianSystemFeedback(
            toast: $viewModel.toastMessage,
            toastAlignment: .top
        )
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $isEditPresented) {
            if let detail = viewModel.detail {
                CommunityIdentificationRequestSheet(
                    speciesName: detail.displayName,
                    scientificName: requestSheetScientificName(for: detail),
                    existingRequestId: detail.requestId,
                    initialNote: detail.note,
                    initialLocationSharing: detail.locationSharing,
                    shouldLoadExistingRequestDetail: false,
                    isSubmitting: viewModel.isUpdatingRequest,
                    onLoadFailed: { message in
                        viewModel.toastMessage = .success(message)
                    },
                    onSubmit: { note, locationSharing in
                        Task {
                            _ = await viewModel.updateRequest(
                                note: note,
                                locationSharing: locationSharing,
                                onUpdated: { isEditPresented = false }
                            )
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $isSearchPresented) {
            if let detail = viewModel.detail {
                CommunityTaxonomySearchSheet(
                    currentPath: detail.currentPath,
                    taxonomyVersionId: detail.taxonomyVersionId,
                    initialSuggestions: detail.suggestedTaxa ?? [],
                    onSelect: handleTaxonSelection
                )
            }
        }
        .sheet(item: $pendingResolver) { context in
            CommunityDisagreementResolverSheet(
                context: context,
                isSubmitting: viewModel.isSubmitting,
                onSubmit: { mode, reasoning, isGenusBestPossible in
                    Task {
                        _ = await viewModel.submit(
                            taxon: context.taxon,
                            disagreementMode: mode,
                            reasoning: reasoning,
                            isGenusBestPossible: isGenusBestPossible,
                            onSubmitted: { pendingResolver = nil }
                        )
                    }
                }
            )
        }
    }

    private func detailContent(_ detail: CommunityIdentificationDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CommunityIdentificationDetailHero(detail: detail)

                CommunityAIIdentificationCard(detail: detail)
                    .padding(.horizontal, 16)

                if let note = detail.note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Requester note")
                            .font(.headline)
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        colorScheme == .light
                            ? Color(red: 0.95, green: 0.96, blue: 0.98)
                            : Color(uiColor: .secondarySystemGroupedBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .padding(.horizontal, 16)
                }

                CommunityIdentificationTimeline(
                    identificationCount: detail.activeIdentificationCount,
                    isConsensusUpdating: detail.isConsensusUpdating,
                    identifications: detail.identifications,
                    onWithdraw: { id in
                        Task { await viewModel.withdraw(identificationId: id) }
                    },
                    onRestore: { id in
                        Task { await viewModel.restore(identificationId: id) }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 88)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .contentMargins(.top, 0, for: .scrollContent)
        .refreshable {
            await viewModel.load()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isSearchPresented = true
            } label: {
                Label("Suggest ID", systemImage: "magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isSubmitting || detail.status != .needsId)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    private func requestSheetScientificName(for detail: CommunityIdentificationDetail) -> String {
        detail.currentScientificName ?? detail.initialScientificName ?? detail.displayRank
    }

    private func handleTaxonSelection(_ taxon: CommunityTaxonSearchResult) {
        guard let detail = viewModel.detail else { return }
        isSearchPresented = false

        switch taxon.relationship(to: detail.currentPath) {
        case .exact, .descendant:
            if taxon.rank == "genus" {
                pendingResolver = CommunityDisagreementResolverContext(
                    taxon: taxon,
                    currentName: detail.displayName,
                    relationship: taxon.relationship(to: detail.currentPath)
                )
                return
            }

            Task {
                _ = await viewModel.submit(
                    taxon: taxon,
                    disagreementMode: .implicitSupport,
                    reasoning: nil,
                    isGenusBestPossible: false
                )
            }
        case .ancestor, .conflict:
            pendingResolver = CommunityDisagreementResolverContext(
                taxon: taxon,
                currentName: detail.displayName,
                relationship: taxon.relationship(to: detail.currentPath)
            )
        }
    }
}
