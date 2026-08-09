import SwiftUI
import XCTest
@testable import PiWork

final class AdaptiveCornerShapeTests: XCTestCase {
    func testUsesSystemConcentricGeometryOnMacOS26() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("ConcentricRectangle is only available on macOS 26 or newer")
        }

        let rect = CGRect(x: 0, y: 0, width: 200, height: 120)
        let actual = adaptiveRoundedShape(cornerRadius: 16).path(in: rect).cgPath
        let expected = ConcentricRectangle(
            corners: .concentric(minimum: .fixed(16))
        ).path(in: rect).cgPath

        XCTAssertEqual(actual, expected)
    }
}
