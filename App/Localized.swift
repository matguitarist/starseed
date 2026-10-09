import ModManagerCore

// Display names for ModManagerCore's enums, from the app's String Catalog
// (the core package's raw values stay English identifiers).

extension ModStatus {
    var title: String {
        switch self {
        case .enabled: String(localized: "Enabled")
        case .disabled: String(localized: "Disabled")
        case .missingDependency: String(localized: "Missing dependency")
        case .needsNewerSMAPI: String(localized: "Needs newer SMAPI")
        case .duplicate: String(localized: "Duplicate")
        case .missingManifest: String(localized: "Missing manifest")
        case .manifestError: String(localized: "Manifest error")
        }
    }
}

extension LogLevel {
    var localizedTitle: String {
        switch self {
        case .trace: String(localized: "Trace", comment: "SMAPI log level")
        case .debug: String(localized: "Debug", comment: "SMAPI log level")
        case .info: String(localized: "Info", comment: "SMAPI log level")
        case .warn: String(localized: "Warning", comment: "SMAPI log level")
        case .error: String(localized: "Error", comment: "SMAPI log level")
        case .alert: String(localized: "Alert", comment: "SMAPI log level")
        }
    }
}

extension NexusSort {
    var localizedTitle: String {
        switch self {
        case .endorsements: String(localized: "Most Endorsed")
        case .downloads: String(localized: "Most Downloaded")
        case .updatedAt: String(localized: "Recently Updated")
        case .createdAt: String(localized: "Newest")
        case .name: String(localized: "Name", comment: "Sort by name")
        }
    }
}

extension CollectionSort {
    var localizedTitle: String {
        switch self {
        case .endorsements: String(localized: "Most Endorsed")
        case .downloads: String(localized: "Most Downloaded")
        case .rating: String(localized: "Top Rated")
        case .updatedAt: String(localized: "Recently Updated")
        case .createdAt: String(localized: "Newest")
        }
    }
}

extension NexusFile {
    /// "Main files", "Optional files"… as on the Nexus files tab.
    var localizedCategory: String {
        switch category {
        case "MAIN": String(localized: "Main files")
        case "OPTIONAL": String(localized: "Optional files")
        case "UPDATE": String(localized: "Updates", comment: "Nexus file category")
        case "MISCELLANEOUS": String(localized: "Miscellaneous")
        case "OLD_VERSION": String(localized: "Old versions")
        case "ARCHIVED": String(localized: "Archived")
        default: category.capitalized
        }
    }
}
