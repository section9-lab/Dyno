import XCTest
@testable import PiWork

/// Tests for the pure-function input processor that powers `OTPInputView`.
/// Covers the cases where naive implementations get caught: pasting a full
/// code, pasting partial digits mid-row, backspace into a blank cell, and
/// type-overflow when the user keeps typing past the last cell.
final class OTPInputProcessorTests: XCTestCase {
    private let length = 6

    // MARK: - Single-digit typing

    func test_typingFirstDigit_advancesFocus() {
        let result = OTPInputProcessor.applyInput("1", to: "", at: 0, length: length)
        XCTAssertEqual(result, .init(code: "1", focusedIndex: 1, isComplete: false))
    }

    func test_typingDigitInMiddle_overwritesAndAdvances() {
        // User has "12_45_" sitting in the row and types into index 2.
        let result = OTPInputProcessor.applyInput("3", to: "1245", at: 2, length: length)
        XCTAssertEqual(result.code, "1235")
        XCTAssertEqual(result.focusedIndex, 3)
    }

    func test_completingLastDigit_marksComplete() {
        let result = OTPInputProcessor.applyInput("6", to: "12345", at: 5, length: length)
        XCTAssertEqual(result, .init(code: "123456", focusedIndex: 5, isComplete: true))
    }

    // MARK: - Paste

    func test_pastingFullCode_overwritesEverything() {
        let result = OTPInputProcessor.applyInput("123456", to: "99", at: 0, length: length)
        XCTAssertEqual(result, .init(code: "123456", focusedIndex: 5, isComplete: true))
    }

    func test_pastingMixedContent_keepsOnlyDigits() {
        // OS pastes sometimes carry surrounding whitespace or unicode marks.
        let result = OTPInputProcessor.applyInput(" 1 2 3 4 5 6 ", to: "", at: 0, length: length)
        XCTAssertEqual(result.code, "123456")
        XCTAssertTrue(result.isComplete)
    }

    func test_pastingPartialDigitsMidRow_fillsFollowingCells() {
        // User had "1" entered, taps cell 2, pastes "234" — should produce
        // "1234" and leave focus on cell 4 (the next empty slot, ready for
        // continued typing). The implementation moves focus past the last
        // digit it placed, not onto it.
        let result = OTPInputProcessor.applyInput("234", to: "1", at: 1, length: length)
        XCTAssertEqual(result.code, "1234")
        XCTAssertEqual(result.focusedIndex, 4)
        XCTAssertFalse(result.isComplete)
    }

    func test_pastingTooManyDigits_truncatesToLength() {
        let result = OTPInputProcessor.applyInput("1234567890", to: "", at: 0, length: length)
        XCTAssertEqual(result.code.count, length)
        XCTAssertEqual(result.code, "123456")
    }

    // MARK: - Reject non-digits

    func test_typingLetter_isNoOp() {
        let result = OTPInputProcessor.applyInput("a", to: "12", at: 2, length: length)
        XCTAssertEqual(result.code, "12")
        XCTAssertEqual(result.focusedIndex, 2)
    }

    func test_typingEmptyString_isNoOp() {
        let result = OTPInputProcessor.applyInput("", to: "123", at: 3, length: length)
        XCTAssertEqual(result.code, "123")
    }

    // MARK: - Backspace

    func test_backspaceOnFilledCell_deletesAndStays() {
        let result = OTPInputProcessor.applyBackspace(to: "1234", at: 2)
        XCTAssertEqual(result, .init(code: "124", focusedIndex: 2))
    }

    func test_backspaceOnEmptyCell_jumpsBackAndClears() {
        // Row is "123" and user is on cell 3 (which is empty).
        let result = OTPInputProcessor.applyBackspace(to: "123", at: 3)
        XCTAssertEqual(result, .init(code: "12", focusedIndex: 2))
    }

    func test_backspaceOnFirstEmptyCell_staysOnZero() {
        let result = OTPInputProcessor.applyBackspace(to: "", at: 0)
        XCTAssertEqual(result, .init(code: "", focusedIndex: 0))
    }

    func test_backspaceOnLastFilledCell_deletesIt() {
        // Code is fully filled, focus on cell 5 — backspace should delete
        // the last digit so the user can correct it without first moving.
        let result = OTPInputProcessor.applyBackspace(to: "123456", at: 5)
        XCTAssertEqual(result, .init(code: "12345", focusedIndex: 5))
    }
}
