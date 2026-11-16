import XCTest
@testable import AIUsageBar

final class ClaudeLoginTests: XCTestCase {
    func testSuccessAndFailureReachCompletionFileWithQuotedPaths() throws {
        for status in [0, 7] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("login ' $ test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let executable = directory.appendingPathComponent("fake ' cli")
            let result = directory.appendingPathComponent("result ' file")
            let command = directory.appendingPathComponent("login.command")
            try "#!/bin/bash\n[ \"$1\" = auth ] && [ \"$2\" = login ] || exit 99\nexit \(status)\n".write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            try ClaudeLogin.script(executable: executable.path, result: result.path).write(to: command, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [command.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, Int32(status))
            XCTAssertEqual(try String(contentsOf: result, encoding: .utf8), String(status))
        }
    }
}
