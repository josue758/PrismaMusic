import XCTest

@testable import PrismaMusic

final class AppUpdateTests: XCTestCase {
    func testOnlyOffersNewerPublishedInstallersFromPrismaRepository() throws {
        func release(_ version: String, draft: Bool = false, owner: String = "josue758", digest: String? = nil)
            -> [String: Any]
        {
            let name = "Prisma-Music-\(version).dmg"
            return [
                "tag_name": "v\(version)", "draft": draft, "body": "Cambios",
                "assets": [
                    [
                        "name": name, "state": "uploaded", "size": 12,
                        "browser_download_url":
                            "https://github.com/\(owner)/PrismaMusic/releases/download/v\(version)/\(name)",
                        "digest": digest ?? "sha256:" + String(repeating: "a", count: 64),
                    ]
                ],
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            release("0.90.0", draft: true), release("0.80.0", owner: "other"), release("0.70.0", digest: "bad"),
            release("0.13.10"), release("0.13.2"), release("0.12.3"),
        ])
        XCTAssertEqual(try AppUpdate.latest(in: data, current: "0.13.1")?.version, "0.13.10")
        XCTAssertNil(try AppUpdate.latest(in: data, current: "0.13.10"))
    }

    func testLiveUpdateDownloadWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["PRISMA_TEST_UPDATE_DOWNLOAD"] == "1" else {
            throw XCTSkip("Optional GitHub installer download")
        }
        let found = try await AppUpdate.check(current: "0.12.2")
        let update = try XCTUnwrap(found)
        let file = try await update.download()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: file.path))
        XCTAssertNotNil(
            try (file as NSURL).resourceValues(forKeys: [.quarantinePropertiesKey])[.quarantinePropertiesKey])
        print("PRISMA_UPDATE verified=\(update.version)")
    }
}
