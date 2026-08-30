import SwiftData
import SwiftUI

extension InsightSheetView {

    @ViewBuilder
    var presentationRoot: some View {
        switch presentationStyle {
        case .sheet:
            NavigationStack {
                configuredContent
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        case .embeddedInScansLibrary:
            configuredContent
        }
    }

    var configuredContent: some View {
        mainContentStack
            .background(alignment: .topLeading) {
                InsightFirstRenderProbe(
                    scanId: inferenceEngine.speciesData?.scanId,
                    onRendered: { scanId in
                        inferenceEngine.recordFirstRenderedFrame(scanId: scanId)
                    }
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { sheetToolbar }
            .toolbarBackground(.visible, for: .bottomBar)
            .toolbarBackground(.ultraThinMaterial, for: .bottomBar)
            .navigationBarBackButtonHidden(presentationStyle.isEmbedded)
            .modifier(EmbeddedInsightBackSwipeModifier(
                isEnabled: presentationStyle.isEmbedded,
                onBack: dismissEmbeddedInsight
            ))
            .background {
                if presentationStyle.isEmbedded {
                    EmbeddedNavigationSwipeBackEnabler()
                        .frame(width: 0, height: 0)
                }
            }
            .modifier(SpeciesDictionaryDestinationModifier(isEnabled: !presentationStyle.isEmbedded))
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedFieldTripOverviewDestination != nil },
                    set: { if !$0 { selectedFieldTripOverviewDestination = nil } }
                )
            ) {
                if let selectedFieldTripOverviewDestination {
                    fieldTripOverviewDetail(for: selectedFieldTripOverviewDestination)
                }
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedFieldTripPublicationRoute != nil },
                    set: { if !$0 { selectedFieldTripPublicationRoute = nil } }
                )
            ) {
                if let selectedFieldTripPublicationRoute {
                    FieldTripPublicationDetailView(
                        publicationId: selectedFieldTripPublicationRoute.publicationId
                    )
                }
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedFieldTripChallengeEntryRoute != nil },
                    set: { if !$0 { selectedFieldTripChallengeEntryRoute = nil } }
                )
            ) {
                if let selectedFieldTripChallengeEntryRoute {
                    FieldTripChallengeEntryDetailView(
                        entryId: selectedFieldTripChallengeEntryRoute.entryId
                    )
                }
            }
            .onAppear(perform: handleAppearance)
            .onDisappear {
                appSettings.suppressInferenceBanners = false
            }
            .task(id: viewModel.resultToolbarRevealKey) {
                // A fresh analysis can finish before its LocalScanRecord reaches this
                // ModelContext. Include completed-record availability in the task key so
                // that late binding schedules the Share and Field chat reveal without a
                // close/reopen cycle. The generation also distinguishes same-ID handoffs.
                let revealKey = viewModel.resultToolbarRevealKey
                guard viewModel.queuedContext == nil,
                      let scanId = revealKey.scanId else { return }
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                } catch {
                    return
                }
                withAnimation(.easeIn(duration: 0.2)) {
                    _ = viewModel.revealBottomBarTools(
                        expectedScanId: scanId,
                        expectedGeneration: revealKey.presentationGeneration
                    )
                }
            }
            .task(id: inferenceEngine.queuedPresentationScanId) {
                guard let scanId = inferenceEngine.queuedPresentationScanId else {
                    return
                }

                // Enqueue happens before the live request, so this normally
                // succeeds on the first pass. Keep the handoff tolerant of a
                // short cross-context propagation delay without ever binding a
                // stale scan after a newer presentation replaces it.
                for _ in 0..<8 {
                    guard !Task.isCancelled,
                          inferenceEngine.queuedPresentationScanId?
                            .caseInsensitiveCompare(scanId) == .orderedSame else {
                        return
                    }
                    if viewModel.bindQueuedPresentationIfAvailable(
                        scanId: scanId,
                        modelContext: modelContext
                    ) {
                        return
                    }
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        return
                    }
                }
            }
            .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
                // Queued scan path: the engine's isProcessing reflects a different pipeline.
                // Skip celebration, haptics, and record-marking — they don't apply here.
                guard viewModel.queuedContext == nil else { return }
                viewModel.evaluateProcessingCompletion(isStillProcessing: isStillProcessing, inferenceEngine: inferenceEngine, modelContext: modelContext)
            }
            .onChange(of: inferenceEngine.speciesData?.scanId) { _, newScanId in
                guard viewModel.state.isInsightChatSheetPresented,
                      let selectedInsightChatScanId,
                      newScanId?.caseInsensitiveCompare(selectedInsightChatScanId) != .orderedSame else {
                    return
                }
                viewModel.state.isInsightChatSheetPresented = false
                self.selectedInsightChatScanId = nil
                self.selectedInsightChatGeneration = nil
            }
            .onChange(of: queuedScan) { oldScan, newScan in
                if let newScan {
                    let changedSubject =
                        oldScan?.id.caseInsensitiveCompare(newScan.id) != .orderedSame
                    viewModel.bindQueuedPresentationPreferringCompletedRecord(
                        newScan,
                        modelContext: modelContext,
                        inferenceEngine: inferenceEngine
                    )
                    guard changedSubject else { return }

                    queuedCompletionHandoffGeneration &+= 1
                    queuedCompletionHandoffScanId = nil
                    selectedInsightChatScanId = nil
                    selectedInsightChatGeneration = nil
                    pendingDeletionScanId = nil
                    pendingDeletionGeneration = nil
                    pendingNewCollectionScanId = nil
                    pendingNewCollectionGeneration = nil
                    return
                }

                // The parent LibraryView proactively loaded the InferenceEngine
                // and cleared the property to signal the handoff is complete.
                // Release the queued context to transition cleanly to the results.
                if let oldScan {
                    viewModel.releaseQueuedPresentation(expectedScanId: oldScan.id)
                }
            }
            .task(id: queuedScan?.id) {
                guard let scanId = queuedScan?.id else { return }
                await attemptQueuedCompletionHandoff(scanId: scanId)
            }
            .onReceive(dependencies.appEvents) { event in
                guard case .scanLibraryChanged = event else { return }
                guard let scanId = viewModel.queuedContext?.id else { return }
                Task { await attemptQueuedCompletionHandoff(scanId: scanId) }
            }
            .task(id: viewModel.scanBoundActionGeneration) {
                // The persistent ID is unchanged by a queued-to-completed handoff.
                // Re-sync against presentation identity so the completed record's
                // Field Notes state becomes available without reopening the sheet.
                viewModel.syncFieldNotesFromCurrentScan(modelContext: modelContext)
            }
            .task(id: fieldTripContributionLoadKey) {
                let scanId = fieldTripContributionLoadKey.scanId
                let generation = viewModel.scanBoundActionGeneration
                await viewModel.loadFieldTripScanContributions(
                    scanId: scanId,
                    expectedGeneration: generation
                )
            }
            .onReceive(dependencies.appEvents) { event in
                guard case .fieldTripScanContributionsInvalidated(let scanId) = event,
                      scanId == viewModel.persistentScanId else { return }
                let generation = viewModel.scanBoundActionGeneration
                Task {
                    await viewModel.loadFieldTripScanContributions(
                        scanId: scanId,
                        expectedGeneration: generation
                    )
                }
            }
            .task(id: viewModel.audioBoostEligibleScanId) {
                guard let scanId = viewModel.audioBoostEligibleScanId else {
                    viewModel.state.isAudioBoostEnabled = false
                    viewModel.state.audioBoostActionToken = nil
                    return
                }
                viewModel.state.isAudioBoostEnabled = InsightAudioBoostPreferenceStore().isEnabled(for: scanId)
                if viewModel.state.isAudioBoostEnabled {
                    AppTelemetry.trackInsightAudioBoost(event: "restored")
                }
            }
            .onChange(of: viewModel.state.isAudioBoostEnabled) { _, enabled in
                guard let scanId = viewModel.audioBoostEligibleScanId else { return }
                InsightAudioBoostPreferenceStore().setEnabled(enabled, for: scanId)
            }
            .task(id: inferenceEngine.speciesData?.scanId) {
                // Queued scans have no speciesData — skip the record fetch and name load.
                guard viewModel.queuedContext == nil else { return }
                if let scanId = inferenceEngine.speciesData?.scanId {
                    // Loop up to 5 times (2.5s max) to allow SwiftData background stores to propagate to the @MainActor context.
                    for _ in 0..<5 {
                        guard !Task.isCancelled,
                              inferenceEngine.speciesData?.scanId?
                                .caseInsensitiveCompare(scanId) == .orderedSame else {
                            return
                        }
                        if viewModel.fetchLocalRecord(for: scanId, modelContext: modelContext) {
                            break
                        }
                        do {
                            try await Task.sleep(nanoseconds: 500_000_000)
                        } catch {
                            return
                        }
                    }
                }
                // Load user's preferred display name for this species so resolvedHeaderTitle reflects it.
                guard !Task.isCancelled,
                      let currentScanId = inferenceEngine.speciesData?.scanId,
                      viewModel.presentedLocalRecordScanId?
                        .caseInsensitiveCompare(currentScanId) == .orderedSame else {
                    return
                }
                if let scientificName = inferenceEngine.speciesData?.scientificName {
                    viewModel.loadPreferredCommonName(for: scientificName, modelContext: modelContext)
                }
                await viewModel.refreshSharedExploreStateFromServer(modelContext: modelContext)
            }
    }

    private func handleAppearance() {
        // Reset stale @State properties from previous presentations natively.
        viewModel.reset()

        // Seed both references immediately so viewModel computed properties
        // resolve on the first frame rather than waiting for
        // InsightContentView's onAppear.
        viewModel.bindSettings(appSettings)
        viewModel.inferenceEngine = inferenceEngine
        var didPromoteQueuedScan = false
        if let queuedScan {
            didPromoteQueuedScan =
                viewModel.bindQueuedPresentationPreferringCompletedRecord(
                    queuedScan,
                    modelContext: modelContext,
                    inferenceEngine: inferenceEngine
                )
        } else if let scanId = inferenceEngine.queuedPresentationScanId {
            // A transport failure can win before the sheet's first onAppear.
            // Bind the durable row synchronously when it is already visible in
            // this context; the keyed task retries brief propagation misses.
            _ = viewModel.bindQueuedPresentationIfAvailable(
                scanId: scanId,
                modelContext: modelContext
            )
        }
        queuedCompletionHandoffGeneration &+= 1
        queuedCompletionHandoffScanId = nil
        selectedInsightChatScanId = nil
        selectedInsightChatGeneration = nil
        pendingDeletionScanId = nil
        pendingDeletionGeneration = nil
        pendingNewCollectionScanId = nil
        pendingNewCollectionGeneration = nil
        if let presentedScanId {
            viewModel.bindPresentedScan(
                scanId: presentedScanId,
                modelContext: modelContext,
                inferenceEngine: inferenceEngine
            )
        }
        if !didPromoteQueuedScan {
            viewModel.evaluateVoiceOverAndCelebration(
                inferenceEngine: inferenceEngine
            )
        }
        // Suppress foreground inference banners while Insight is visible.
        appSettings.suppressInferenceBanners = true
        appSettings.hasUnseenScan = false
        dependencies.updateAppIconBadge()
    }

    private var fieldTripContributionLoadKey: InsightFieldTripContributionLoadKey {
        let authentication = dependencies.authenticationSnapshot()
        return InsightFieldTripContributionLoadKey(
            scanId: viewModel.persistentScanId,
            isAuthenticated: authentication.isAuthenticated,
            accountId: authentication.accountID
        )
    }

    @ViewBuilder
    private func fieldTripOverviewDetail(
        for destination: InsightFieldTripOverviewDestination
    ) -> some View {
        switch destination {
        case .standardOuting(let templateId):
            FieldTripTemplateDetailView(
                templateId: templateId,
                focusedChecklistItemId: nil,
                onOpenCompletedScan: openFieldTripCompletedScan,
                onOpenPublication: { publicationId in
                    selectedFieldTripPublicationRoute = FieldTripPublicationRoute(
                        publicationId: publicationId
                    )
                },
                onOpenAuthorProfile: openFieldTripAuthorProfile
            )
        case .event(let challengeId):
            FieldTripChallengeDetailView(
                challengeId: challengeId,
                onOpenEntry: { entryId in
                    selectedFieldTripChallengeEntryRoute = FieldTripChallengeEntryRoute(
                        entryId: entryId
                    )
                },
                onOpenAuthorProfile: openFieldTripChallengeAuthorProfile
            )
        }
    }

    private func openFieldTripCompletedScan(_ scanId: String) {
        guard viewModel.bindPresentedScan(
            scanId: scanId,
            modelContext: modelContext,
            inferenceEngine: inferenceEngine
        ) else {
            dependencies.errorFeedback()
            viewModel.state.toastMessage = .warning(
                "This scan is not available on this device."
            )
            return
        }

        dependencies.selectionFeedback()
        presentedScanId = scanId
        selectedFieldTripOverviewDestination = nil
    }

    private func openFieldTripAuthorProfile(
        _ publication: FieldTripRecentPublication
    ) {
        let route = ExploreAuthorProfileRoute(
            authorUserId: publication.authorUserId,
            authorName: publication.authorName,
            authorUsername: publication.authorUsername,
            authorAvatarUrl: publication.authorAvatarUrl
        )
        guard requestShellPresentation(.fieldTripAuthor(route)) else { return }
        dependencies.selectionFeedback()
    }

    private func openFieldTripChallengeAuthorProfile(
        _ entry: FieldTripChallengeEntry
    ) {
        let route = ExploreAuthorProfileRoute(
            authorUserId: entry.authorUserId,
            authorName: entry.authorName,
            authorUsername: entry.authorUsername,
            authorAvatarUrl: entry.authorAvatarUrl
        )
        guard requestShellPresentation(.fieldTripAuthor(route)) else { return }
        dependencies.selectionFeedback()
    }

    private func attemptQueuedCompletionHandoff(scanId: String) async {
        if queuedCompletionHandoffScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame {
            return
        }
        queuedCompletionHandoffGeneration &+= 1
        let generation = queuedCompletionHandoffGeneration
        queuedCompletionHandoffScanId = scanId
        defer {
            if queuedCompletionHandoffGeneration == generation {
                queuedCompletionHandoffScanId = nil
            }
        }

        for attempt in 0..<8 {
            let isCurrentQueuedScan = viewModel.queuedContext?.id
                .caseInsensitiveCompare(scanId) == .orderedSame
            guard !Task.isCancelled,
                  queuedCompletionHandoffGeneration == generation,
                  isCurrentQueuedScan else {
                return
            }
            if viewModel.promoteQueuedScanIfLocalRecordExists(
                scanId: scanId,
                modelContext: modelContext,
                inferenceEngine: inferenceEngine
            ) {
                appSettings.hasUnseenScan = false
                dependencies.updateAppIconBadge()
                return
            }

            if attempt < 7 {
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                } catch {
                    return
                }
            }
        }

        MerianLog.data.debug(
            "InsightSheetView.attemptQueuedCompletionHandoff: no completed local record visible scanId=\(scanId, privacy: .private)"
        )
    }

    private func dismissEmbeddedInsight() {
        isPresented = false
        dismiss()
    }
}
