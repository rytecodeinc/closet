//
//  ProfileAvatarLocalStorage.swift
//  closet
//
//  On-device profile avatar files for builds without cloud avatar sync (e.g. TestFlight tier).
//

import Foundation

enum ProfileAvatarLocalStorage {
    private static let folderName = "ProfileAvatars"

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func fileURL(for userId: UUID) -> URL {
        directoryURL.appendingPathComponent("\(userId.uuidString).jpg", isDirectory: false)
    }

    static func hasSavedAvatar(userId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: userId).path)
    }

    static func canonicalStoredURLString(for userId: UUID) -> String {
        fileURL(for: userId).absoluteString
    }

    /// Writes JPEG bytes and returns a `file://` URL suitable for Core Data `avatarUrl`.
    @discardableResult
    static func saveJPEG(userId: UUID, data: Data) throws -> URL {
        let url = fileURL(for: userId)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func delete(userId: UUID) {
        let url = fileURL(for: userId)
        try? FileManager.default.removeItem(at: url)
    }
}
