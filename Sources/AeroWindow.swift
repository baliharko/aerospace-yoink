import AppKit

struct AeroWindow {
    let id: Int
    let workspace: String
    let appName: String
    let title: String
    let icon: NSImage

    func matches(_ query: String) -> Bool {
        if query.isEmpty { return true }
        let q = query.lowercased()
        return appName.lowercased().contains(q)
            || title.lowercased().contains(q)
            || workspace.lowercased().contains(q)
    }
}
