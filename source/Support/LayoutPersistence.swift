import Foundation

enum LayoutPersistence {
    private static let savedLayoutsDefaultsKey = "savedWindowLayouts.v1"
    private static let selectedLayoutIDDefaultsKey = "selectedSavedLayoutID.v1"

    static func loadSavedLayouts() -> [SavedLayout] {
        guard
            let data = UserDefaults.standard.data(forKey: savedLayoutsDefaultsKey),
            let layouts = try? JSONDecoder().decode([SavedLayout].self, from: data)
        else {
            return []
        }

        return layouts
    }

    static func saveLayouts(_ layouts: [SavedLayout]) {
        guard let data = try? JSONEncoder().encode(layouts) else {
            return
        }

        UserDefaults.standard.set(data, forKey: savedLayoutsDefaultsKey)
    }

    static var selectedLayoutID: String {
        get {
            UserDefaults.standard.string(forKey: selectedLayoutIDDefaultsKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: selectedLayoutIDDefaultsKey)
        }
    }
}
