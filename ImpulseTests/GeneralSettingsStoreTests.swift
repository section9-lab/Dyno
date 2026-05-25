import XCTest
@testable import Impulse

final class GeneralSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "GeneralSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_loadOCREnabled_defaultsToFalseWhenUnset() {
        XCTAssertFalse(GeneralSettingsStore.loadOCREnabled(defaults: defaults))
    }

    func test_saveOCREnabled_roundTripsExplicitValues() {
        GeneralSettingsStore.saveOCREnabled(true, defaults: defaults)
        XCTAssertTrue(GeneralSettingsStore.loadOCREnabled(defaults: defaults))

        GeneralSettingsStore.saveOCREnabled(false, defaults: defaults)
        XCTAssertFalse(GeneralSettingsStore.loadOCREnabled(defaults: defaults))
    }

    func test_loadVoiceShortcut_defaultsToOptionWhenUnset() {
        XCTAssertEqual(GeneralSettingsStore.loadVoiceShortcut(defaults: defaults), "Option")
    }

    func test_saveVoiceShortcut_roundTripsExplicitValue() {
        GeneralSettingsStore.saveVoiceShortcut("Control", defaults: defaults)
        XCTAssertEqual(GeneralSettingsStore.loadVoiceShortcut(defaults: defaults), "Control")
    }

    func test_voiceShortcut_fallsBackToOptionForUnknownStoredValue() {
        XCTAssertEqual(VoiceShortcut(storedValue: "Unknown"), .option)
    }

    func test_voiceShortcut_matchesConfiguredModifierOnly() {
        XCTAssertTrue(VoiceShortcut.option.isPressed(in: [.option]))
        XCTAssertTrue(VoiceShortcut.command.isPressed(in: [.command, .shift]))
        XCTAssertFalse(VoiceShortcut.control.isPressed(in: [.option]))
    }
}
