enum SpeciesDictionaryTaxonomyPresentation {
    static func data(
        from taxonomy: SpeciesDictionaryTaxonomy?
    ) -> TaxonomyData? {
        guard let taxonomy else { return nil }
        let data = TaxonomyData(
            kingdom: taxonomy.kingdom,
            phylum: taxonomy.phylum,
            className: taxonomy.className,
            order: taxonomy.order,
            family: taxonomy.family,
            genus: taxonomy.genus
        )

        return [
            data.kingdom,
            data.phylum,
            data.className,
            data.order,
            data.family,
            data.genus
        ].contains { $0?.trimmedNonEmptyValue != nil } ? data : nil
    }
}
