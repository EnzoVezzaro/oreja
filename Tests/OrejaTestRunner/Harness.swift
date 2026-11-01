import Foundation

/// A tiny self-contained test harness.
///
/// The development machine has Command Line Tools only (no Xcode, therefore no XCTest or Swift
/// Testing runtime), so the suite runs as a normal Swift executable. `swift test` /
/// XCTest can be added once a full Xcode toolchain is available; the cases themselves are plain
/// functions and do not depend on this harness beyond the assertions.
@MainActor
final class Harness {
    struct Failure {
        var test: String
        var message: String
        var location: String
    }

    private(set) var failures: [Failure] = []
    private(set) var assertions = 0
    private(set) var passedTests = 0
    private(set) var failedTests = 0
    private var currentTest = ""

    var onlyFilter: String?

    func run(_ name: String, _ body: () throws -> Void) {
        runBody(name) { try body() }
    }

    func runAsync(_ name: String, _ body: () async throws -> Void) async {
        if let onlyFilter, !name.localizedCaseInsensitiveContains(onlyFilter) { return }
        currentTest = name
        let failuresBefore = failures.count
        do {
            try await body()
        } catch {
            record("threw \(error)")
        }
        if failures.count == failuresBefore {
            passedTests += 1
            print("  PASS  \(name)")
        } else {
            failedTests += 1
            print("  FAIL  \(name)")
        }
    }

    private func runBody(_ name: String, _ body: () throws -> Void) {
        if let onlyFilter, !name.localizedCaseInsensitiveContains(onlyFilter) { return }
        currentTest = name
        let failuresBefore = failures.count
        do {
            try body()
        } catch {
            record("threw \(error)")
        }
        if failures.count == failuresBefore {
            passedTests += 1
            print("  PASS  \(name)")
        } else {
            failedTests += 1
            print("  FAIL  \(name)")
        }
    }

    func expect(_ condition: Bool, _ message: @autoclosure () -> String = "condition failed", file: StaticString = #fileID, line: UInt = #line) {
        assertions += 1
        if !condition {
            record(message(), file: file, line: line)
        }
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
        assertions += 1
        if actual != expected {
            let detail = message().isEmpty ? "" : " — \(message())"
            record("expected \(expected), got \(actual)\(detail)", file: file, line: line)
        }
    }

    func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 0.0001, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
        assertions += 1
        if abs(actual - expected) > tolerance {
            let detail = message().isEmpty ? "" : " — \(message())"
            record("expected \(expected) ± \(tolerance), got \(actual)\(detail)", file: file, line: line)
        }
    }

    private func record(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        failures.append(Failure(test: currentTest, message: message, location: "\(file):\(line)"))
        print("        ↳ \(message) (\(file):\(line))")
    }

    var summary: String {
        "\(passedTests) passed, \(failedTests) failed, \(assertions) assertions"
    }
}
