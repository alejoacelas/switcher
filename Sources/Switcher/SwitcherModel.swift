import Foundation

struct AppCandidate: Equatable {
    let bundleIdentifier: String
    let name: String
    let activationRank: Int
    var isHidden = false
    var hasVisibleWindow = true
}

enum SwitcherModel {
    static let excludedBundleIdentifiers = Set([
        "com.apple.finder",
        "com.McAfee.McAfeeSafariHost",
        "com.electron.wispr-flow",
        "com.granola.app",
    ])

    static func visibleCandidates(_ candidates: [AppCandidate], query: String = "") -> [AppCandidate] {
        candidates
            .filter { !excludedBundleIdentifiers.contains($0.bundleIdentifier) }
            .filter { !$0.isHidden && $0.hasVisibleWindow }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted {
                if $0.activationRank == $1.activationRank { return $0.name < $1.name }
                return $0.activationRank < $1.activationRank
            }
    }

    static func movedIndex(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + delta % count + count) % count
    }
}
