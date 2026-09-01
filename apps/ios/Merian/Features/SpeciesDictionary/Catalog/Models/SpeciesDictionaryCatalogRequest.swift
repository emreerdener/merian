import Foundation

struct SpeciesDictionaryCatalogSelection: Hashable {
    let category: SpeciesDictionaryCatalogCategory
    let region: String?
    let group: String?
    let query: String?

    init(
        category: SpeciesDictionaryCatalogCategory,
        region: String?,
        group: String?,
        query: String?
    ) {
        self.category = category
        self.region = region?.trimmedNonEmptyValue
        self.group = group?.trimmedNonEmptyValue
        self.query = query?.trimmedNonEmptyValue
    }
}

struct SpeciesDictionaryCatalogPageRequest: Equatable {
    let selection: SpeciesDictionaryCatalogSelection
    let limit: Int
    let cursor: SpeciesDictionaryCatalogCursor?

    var category: SpeciesDictionaryCatalogCategory { selection.category }
    var region: String? { selection.region }
    var group: String? { selection.group }
    var query: String? { selection.query }

    init(
        category: SpeciesDictionaryCatalogCategory,
        region: String?,
        group: String?,
        query: String?,
        limit: Int,
        cursor: SpeciesDictionaryCatalogCursor? = nil
    ) {
        self.init(
            selection: SpeciesDictionaryCatalogSelection(
                category: category,
                region: region,
                group: group,
                query: query
            ),
            limit: limit,
            cursor: cursor
        )
    }

    init(
        selection: SpeciesDictionaryCatalogSelection,
        limit: Int,
        cursor: SpeciesDictionaryCatalogCursor? = nil
    ) {
        self.selection = selection
        self.limit = limit
        self.cursor = cursor
    }
}
