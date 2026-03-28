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

    func matches(_ query: String) -> Bool {
        if query.isEmpty { return true }
        let q = query.lowercased()
        return appNameLower.contains(q)
            || titleLower.contains(q)
            || workspaceLower.contains(q)
    }
}
