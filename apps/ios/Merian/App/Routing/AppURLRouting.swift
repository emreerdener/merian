import Foundation

enum MerianOpenURLRoute: Equatable {
    case handledByGoogle
    case merianDeepLink
    case externalImageImport
    case supabaseAuthentication

    static func classify(
        _ url: URL,
        googleHandled: Bool
    ) -> MerianOpenURLRoute {
        if googleHandled {
            return .handledByGoogle
        }
        if MerianDeepLinkRoute(url: url) != nil {
            return .merianDeepLink
        }
        if url.isFileURL {
            return .externalImageImport
        }
        return .supabaseAuthentication
    }
}
