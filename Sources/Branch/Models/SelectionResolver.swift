import AppKit
import Foundation

struct SelectionResult: Equatable {
    let selectedURLs: Set<URL>
    let anchorURL: URL?
}

enum SelectionResolver {
    static func resolve(
        clickedURL: URL,
        orderedURLs: [URL],
        selectedURLs: Set<URL>,
        anchorURL: URL?,
        modifiers: NSEvent.ModifierFlags
    ) -> SelectionResult {
        let isAdditive = modifiers.contains(.command) || modifiers.contains(.option)

        if modifiers.contains(.shift),
           let anchorURL,
           let anchorIndex = orderedURLs.firstIndex(of: anchorURL),
           let clickedIndex = orderedURLs.firstIndex(of: clickedURL) {
            let range = Set(orderedURLs[min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)])
            return SelectionResult(
                selectedURLs: isAdditive ? selectedURLs.union(range) : range,
                anchorURL: anchorURL
            )
        }

        if isAdditive {
            var updated = selectedURLs
            if updated.contains(clickedURL) { updated.remove(clickedURL) }
            else { updated.insert(clickedURL) }
            return SelectionResult(selectedURLs: updated, anchorURL: clickedURL)
        }

        return SelectionResult(selectedURLs: [clickedURL], anchorURL: clickedURL)
    }
}
