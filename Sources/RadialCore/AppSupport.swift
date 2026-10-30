import Foundation

/// Where the app keeps its JSON files, and the one-time carry-over from before the rename.
///
/// The app was called Safari Radial and kept its data in `Application Support/SafariRadial`.
/// Renaming it must not lose anyone's slots or settings, so the first time a file is asked for
/// and is missing from the new folder, the old copy is *copied* across. Copied, not moved: the
/// old folder is left exactly as it was, so a failed or unwanted migration costs nothing and an
/// older build still finds its data.
public enum AppSupport {
    public static let folderName = "Pelorus"
    public static let legacyFolderName = "SafariRadial"

    /// The location of `fileName` inside the app's folder.
    ///
    /// `base` is Application Support unless a test passes a scratch directory.
    public static func url(
        for fileName: String,
        base: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let root = base
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let current = root.appendingPathComponent(folderName).appendingPathComponent(fileName)
        let legacy = root.appendingPathComponent(legacyFolderName).appendingPathComponent(fileName)

        if !fileManager.fileExists(atPath: current.path), fileManager.fileExists(atPath: legacy.path) {
            do {
                try fileManager.createDirectory(
                    at: current.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: legacy, to: current)
            } catch {
                NSLog("Pelorus: could not carry \(fileName) over from \(legacyFolderName): \(error.localizedDescription)")
                // Better to keep reading the old copy than to start from an empty dial.
                return legacy
            }
        }
        return current
    }
}
