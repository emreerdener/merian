extension ExploreMapViewModel {
    func clearSpeciesFilters() async {
        await setSpeciesFilters([])
    }

    func clearMediaTypeFilters() async {
        await setMediaTypeFilters([])
    }

    func clearFilters() async {
        guard hasActiveFilters else { return }
        invalidateFocusedPost()
        selectedSpeciesCategories = []
        selectedMediaTypes = []
        selectedPostId = nil
        await searchCurrentArea()
    }

    func toggleSpeciesFilter(_ category: ExploreMapSpeciesCategory) async {
        var nextFilters = selectedSpeciesCategories
        if nextFilters.contains(category) {
            nextFilters.remove(category)
        } else {
            nextFilters.insert(category)
        }
        await setSpeciesFilters(nextFilters)
    }

    func setSpeciesFilters(_ categories: Set<ExploreMapSpeciesCategory>) async {
        guard categories != selectedSpeciesCategories else { return }
        invalidateFocusedPost()
        selectedSpeciesCategories = categories
        selectedPostId = nil
        await searchCurrentArea()
    }

    func toggleMediaTypeFilter(_ mediaType: ExploreMediaKind) async {
        var nextFilters = selectedMediaTypes
        if nextFilters.contains(mediaType) {
            nextFilters.remove(mediaType)
        } else {
            nextFilters.insert(mediaType)
        }
        await setMediaTypeFilters(nextFilters)
    }

    func setMediaTypeFilters(_ mediaTypes: Set<ExploreMediaKind>) async {
        guard mediaTypes != selectedMediaTypes else { return }
        invalidateFocusedPost()
        selectedMediaTypes = mediaTypes
        selectedPostId = nil
        await searchCurrentArea()
    }
}
