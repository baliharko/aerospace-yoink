import AppKit

struct AeroWindow {
    let id: Int
    let workspace: String
    let appName: String
    let title: String
    let icon: NSImage

    // Pre-computed for search — avoids repeated lowercased() on every keystroke
    private let appNameLower: String
    private let titleLower: String
    private let workspaceLower: String

    init(id: Int, workspace: String, appName: String, title: String, icon: NSImage) {
        self.id = id
        self.workspace = workspace
        self.appName = appName
        self.title = title
        self.icon = icon
        self.appNameLower = appName.lowercased()
        self.titleLower = title.lowercased()
        self.workspaceLower = workspace.lowercased()
    }

    /// Splits a filter query into lowercased terms — once per search, not
    /// once per window.
    static func searchTerms(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every term must appear in the app name, title, or workspace, in any
    /// order, so "chrome github" finds a Chrome window whose title mentions
    /// GitHub. Terms come from `searchTerms(_:)`; none matches everything.
    func matches(terms: [String]) -> Bool {
        terms.allSatisfy { term in
            appNameLower.contains(term)
                || titleLower.contains(term)
                || workspaceLower.contains(term)
        }
    }
}
