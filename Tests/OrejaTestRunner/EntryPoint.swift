import Foundation

@main
struct TestMain {
    @MainActor
    static func main() async {
        let harness = Harness()
        if CommandLine.arguments.count > 1 {
            harness.onlyFilter = CommandLine.arguments[1]
        }

        print("Oreja test suite")
        print("================")

        await runCoordinatorSuite(harness)
        runDetectionSuite(harness)
        await runMediaAndSettingsSuite(harness)
        runAudioSourceSuite(harness)
        runMonitorRecoverySuite(harness)
        await runHookSuite(harness)

        print("\n\(harness.summary)")
        if !harness.failures.isEmpty {
            print("\nFailures:")
            for failure in harness.failures {
                print("  \(failure.test): \(failure.message) [\(failure.location)]")
            }
            exit(1)
        }
        exit(0)
    }
}
