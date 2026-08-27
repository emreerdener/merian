import SwiftUI

struct ExploreAuthorProfileSheet: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let route: ExploreAuthorProfileRoute

    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ExploreAuthorProfileContent(
                viewModel: viewModel,
                route: route,
                presentation: .sheet,
                onClose: { dismiss() },
                onOpenPostRoute: { route in
                    navigationPath.append(route)
                },
                onOpenPublication: { publicationId in
                    navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                },
                onOpenTemplate: { templateId in
                    navigationPath.append(FieldTripTemplateRoute(templateId: templateId))
                }
            )
            .navigationDestination(for: ExplorePostRoute.self) { route in
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: route.postId,
                    shouldFocusCommentComposer: route.shouldFocusCommentComposer,
                    shouldOpenInsight: route.shouldOpenInsight,
                    targetCommentId: route.targetCommentId,
                    targetReplyParentCommentId: route.targetReplyParentCommentId,
                    allowsInsightPresentation: false,
                    allowsAuthorProfilePresentation: false
                )
            }
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false,
                    exploreViewModel: viewModel
                )
            }
            .navigationDestination(for: FieldTripPublicationRoute.self) { route in
                FieldTripPublicationDetailView(publicationId: route.publicationId)
            }
            .navigationDestination(for: FieldTripTemplateRoute.self) { route in
                FieldTripTemplateDetailView(
                    reference: route.reference,
                    focusedChecklistItemId: route.focusedChecklistItemId,
                    onOpenCompletedScan: { _ in },
                    onOpenPublication: { publicationId in
                        navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                    },
                    onOpenAuthorProfile: { _ in }
                )
            }
        }
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
    }
}
