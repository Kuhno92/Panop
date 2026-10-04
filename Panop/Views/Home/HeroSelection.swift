import PanopDiscover

/// Which titles the hero carousel features: the first usable title of each suggestion row, in the rows' order,
/// so the carousel is a taste of the page below it and no title is chosen by anything but the rails.
nonisolated enum HeroSelection {
    static let limit = 6
    /// Fewer than this and the carousel adds titles that have only a poster, to be worth sliding.
    private static let wanted = 3

    static func rows(
        rails: [Rail],
        rows: [String: CatalogRow],
        backdrop: (CatalogRow) -> String?,
        limit: Int = HeroSelection.limit
    ) -> [CatalogRow] {
        // Wide artwork first: a hero made of enlarged posters is the fallback, not the aim.
        var chosen = pick(from: rails, rows: rows, limit: limit, already: [], accepting: { backdrop($0) != nil })
        if chosen.count < wanted {
            chosen += pick(
                from: rails,
                rows: rows,
                limit: wanted - chosen.count,
                already: Set(chosen.map(\.id)),
                accepting: { _ in true }
            )
        }
        return chosen
    }

    private static func pick(
        from rails: [Rail],
        rows: [String: CatalogRow],
        limit: Int,
        already: Set<String>,
        accepting: (CatalogRow) -> Bool
    ) -> [CatalogRow] {
        var seen = already
        var result: [CatalogRow] = []
        for rail in rails where result.count < limit {
            let found = rail.keys.lazy.compactMap { rows[$0] }.first {
                $0.iconURL != nil && !seen.contains($0.id) && accepting($0)
            }
            if let found {
                seen.insert(found.id)
                result.append(found)
            }
        }
        return result
    }
}
