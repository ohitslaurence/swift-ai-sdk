#if canImport(SwiftUI)
    import AISwiftUI
    import XCTest

    final class AISwiftUISmokeTests: XCTestCase {
        @MainActor
        func test_streamStateInitializes() {
            _ = AIStreamState()
        }
    }
#endif
