import Foundation

/// Where MoniMac keeps its files: ~/Library/Application Support/MoniMac.
public enum AppFiles {
    public static let directory = URL.applicationSupportDirectory.appending(path: "MoniMac")
}
