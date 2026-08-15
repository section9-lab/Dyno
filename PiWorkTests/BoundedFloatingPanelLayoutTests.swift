import XCTest
@testable import PiWork

final class BoundedFloatingPanelLayoutTests: XCTestCase {
    func testFloatingPanelDrawsAPointerBackToItsAnchor() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("PiWork/Core/UI/InWindowFloatingPanel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("anchorFrame: CGRect?"))
        XCTAssertTrue(source.contains("FloatingPanelPointer"))
        XCTAssertTrue(source.contains("pointerX"))
    }

    func testPanelShrinksInsideAvailableContentBounds() {
        let layout = BoundedFloatingPanelLayout(
            idealWidth: 460,
            idealMaximumHeight: 520,
            inset: 16
        )

        XCTAssertEqual(
            layout.size(in: CGSize(width: 380, height: 420)),
            CGSize(width: 348, height: 388)
        )
    }

    func testAnchoredPanelPointsToButtonAndKeepsItsBodyInsideBounds() throws {
        let layout = BoundedFloatingPanelLayout(
            idealWidth: 460,
            idealMaximumHeight: 520,
            inset: 16
        )
        let anchor = CGRect(x: 300, y: 48, width: 34, height: 34)

        let placement = layout.placement(
            in: CGSize(width: 380, height: 420),
            anchoredTo: anchor
        )

        XCTAssertEqual(placement.size, CGSize(width: 348, height: 310))
        XCTAssertEqual(placement.origin, CGPoint(x: 16, y: 94))
        XCTAssertEqual(
            placement.origin.x + (try XCTUnwrap(placement.pointerX)),
            anchor.midX
        )
        XCTAssertLessThanOrEqual(
            placement.origin.y + placement.size.height,
            420 - layout.inset
        )
    }

    func testPanelKeepsIdealSizeWhenContentBoundsAreLargeEnough() {
        let layout = BoundedFloatingPanelLayout(
            idealWidth: 420,
            idealMaximumHeight: 480,
            inset: 16
        )

        XCTAssertEqual(
            layout.size(in: CGSize(width: 900, height: 680)),
            CGSize(width: 420, height: 480)
        )
    }
}
