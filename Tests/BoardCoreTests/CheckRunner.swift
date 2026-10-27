import Foundation

// A small dependency-free harness: Apple's Command Line Tools don't include XCTest.
// These checks exercise actual filesystem operations, not a mock filesystem.
private var failures: [String] = []
private func record(_ message: String, file: StaticString, line: UInt) { failures.append("\(file):\(line): \(message)") }

func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(); let b = try rhs(); if a != b { record("Expected \(a) == \(b). \(message)", file: file, line: line) } }
    catch { record("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertNotEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { if try lhs() == rhs() { record("Expected unequal values", file: file, line: line) } }
    catch { record("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertTrue(_ condition: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !condition() { record("Expected true", file: file, line: line) } }
    catch { record("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertFalse(_ condition: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try condition() { record("Expected false", file: file, line: line) } }
    catch { record("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ operation: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try operation(); record("Expected an error. \(message)", file: file, line: line) } catch { }
}
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "BoardCoreChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected a non-nil value"]) }; return value
}

@main
struct CheckRunner {
    static func main() {
        let suite = LibraryRepositoryTests()
        let checks: [(String, () throws -> Void)] = [
            ("原子保存与任务/备忘/链接恢复", suite.testAtomicMetadataRoundTrip),
            ("原文件逐字节复制与同名保护", suite.testImportCopiesOriginalBytesAndDoesNotOverwriteNames),
            ("递归文件夹导入与 Finder 变更同步", suite.testNestedDirectoryImportAndFinderChangesAreDiscovered),
            ("永久删除真实文件并保留导入源", suite.testPermanentDeleteRemovesRealManagedFileButPreservesSource),
            ("拒绝删除资料库外文件和项目根目录", suite.testDeletionRejectsOutsidePathsAndProjectRoot),
            ("符号链接和目录穿越保护", suite.testSymlinkAndTraversalProtection),
            ("无效符号链接保护", suite.testBrokenSymlinksAreRejected),
            ("完整备份与无覆盖合并恢复", suite.testBackupIncludesOriginalFilesAndRestoreMergesWithoutOverwrite),
            ("阻止递归备份", suite.testBackupInsideLibraryIsRejected),
            ("损坏资料库保持原样", suite.testCorruptManifestIsNotReplaced),
            ("索引缺失时不静默清空", suite.testMissingManifestWithExistingFilesIsNotSilentlyReset),
            ("无效名称和不安全索引保护", suite.testInvalidNamesAndUnsafeManifestAreRejected),
            ("磁盘重命名、移动和导出", suite.testRealRenameMoveAndFileExport),
            ("部分导入失败的准确报告", suite.testPartialImportReportsFailureAndKeepsSuccessfulOriginal),
            ("恢复失败后回滚目录和索引", suite.testRestoreFailureRollsBackCopiedProjectsAndManifest)
        ]
        for (name, check) in checks {
            let previous = failures.count
            do { try suite.setUpWithError(); try check() }
            catch { failures.append("\(name): \(error)") }
            do { try suite.tearDownWithError() } catch { failures.append("清理测试目录失败：\(error)") }
            print("\(previous == failures.count ? "PASS" : "FAIL")  \(name)")
        }
        for failure in failures { print(failure) }
        print("\(checks.count) checks, \(failures.count) failures")
        if !failures.isEmpty { exit(1) }
    }
}
