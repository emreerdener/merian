enum SpeciesDictionaryCategoryRoute: Hashable {
    case catalog(
        title: String,
        category: SpeciesDictionaryCatalogCategory,
        region: String?
    )
    case group(title: String, group: String)
    case taxonomy
    case regions
}
