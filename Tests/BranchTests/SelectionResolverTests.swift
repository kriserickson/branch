import AppKit
import Foundation
import Testing
@testable import Branch

struct SelectionResolverTests {
    private let urls = (0..<6).map { URL(fileURLWithPath: "/item-\($0)") }

    @Test func shiftSelectsInclusiveRangeFromAnchor() {
        let result = SelectionResolver.resolve(
            clickedURL: urls[4], orderedURLs: urls, selectedURLs: [urls[1]],
            anchorURL: urls[1], modifiers: [.shift]
        )
        #expect(result.selectedURLs == Set(urls[1...4]))
        #expect(result.anchorURL == urls[1])
    }

    @Test func optionTogglesIndividualItemsAndMovesAnchor() {
        let result = SelectionResolver.resolve(
            clickedURL: urls[4], orderedURLs: urls, selectedURLs: [urls[1]],
            anchorURL: urls[1], modifiers: [.option]
        )
        #expect(result.selectedURLs == [urls[1], urls[4]])
        #expect(result.anchorURL == urls[4])
    }

    @Test func additiveShiftUnionsRangeWithExistingSelection() {
        let result = SelectionResolver.resolve(
            clickedURL: urls[4], orderedURLs: urls, selectedURLs: [urls[0], urls[2]],
            anchorURL: urls[2], modifiers: [.command, .shift]
        )
        #expect(result.selectedURLs == [urls[0], urls[2], urls[3], urls[4]])
    }
}
