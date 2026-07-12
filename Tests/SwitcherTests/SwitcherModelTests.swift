import Testing
@testable import Switcher

@Test func filtersConfiguredExceptionsAndOrdersByRecency() {
    let input = [
        AppCandidate(bundleIdentifier: "com.apple.finder", name: "Finder", activationRank: 0),
        AppCandidate(bundleIdentifier: "com.apple.Safari", name: "Safari", activationRank: 2),
        AppCandidate(bundleIdentifier: "com.apple.Terminal", name: "Terminal", activationRank: 1),
    ]
    #expect(SwitcherModel.visibleCandidates(input).map(\.name) == ["Terminal", "Safari"])
}

@Test func searchesWithoutCaseSensitivity() {
    let input = [AppCandidate(bundleIdentifier: "com.apple.Safari", name: "Safari", activationRank: 0)]
    #expect(SwitcherModel.visibleCandidates(input, query: "SAF").count == 1)
}

@Test func excludesHiddenMinimizedAndWindowlessApps() {
    let input = [
        AppCandidate(bundleIdentifier: "visible", name: "Visible", activationRank: 0),
        AppCandidate(bundleIdentifier: "hidden", name: "Hidden", activationRank: 1, isHidden: true),
        AppCandidate(bundleIdentifier: "without-window", name: "No window", activationRank: 2, hasVisibleWindow: false),
    ]
    #expect(SwitcherModel.visibleCandidates(input).map(\.name) == ["Visible"])
}

@Test func selectionWrapsBothWays() {
    #expect(SwitcherModel.movedIndex(2, by: 1, count: 3) == 0)
    #expect(SwitcherModel.movedIndex(0, by: -1, count: 3) == 2)
}
