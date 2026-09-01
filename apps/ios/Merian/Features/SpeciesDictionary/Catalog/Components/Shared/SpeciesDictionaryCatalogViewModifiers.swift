import SwiftUI

struct SpeciesDictionaryCatalogSearchModifier: ViewModifier {
    @Binding var searchText: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search species"
            )
        } else {
            content
        }
    }
}

struct SpeciesDictionaryBottomSearchModifier: ViewModifier {
    @Binding var searchText: String
    let isEnabled: Bool

    @State private var isSearchPresented = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .toolbar,
                prompt: "Search species"
            )
        } else {
            content
        }
    }
}

struct SpeciesDictionaryCatalogTitleModifier: ViewModifier {
    let title: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationTitle(title)
        } else {
            content
        }
    }
}
