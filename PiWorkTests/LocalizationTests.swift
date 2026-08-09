import XCTest
@testable import PiWork

final class LocalizationTests: XCTestCase {
    @MainActor
    func testEnglishIsTheDefaultAndLanguageChoicePersists() throws {
        let suiteName = "LocalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LanguageStore(defaults: defaults)

        XCTAssertEqual(store.language, .english)
        XCTAssertEqual(
            AppLanguage.allCases.map(\.rawValue),
            ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es"]
        )

        store.language = .japanese

        XCTAssertEqual(LanguageStore(defaults: defaults).language, .japanese)
    }

    func testEverySupportedLanguageContainsTheCompleteEnglishCatalog() throws {
        let english = try localizationEntries(languageCode: "en")

        XCTAssertGreaterThanOrEqual(english.count, 120)
        XCTAssertEqual(english["settings.title"], "Settings")

        for language in ["zh-Hans", "zh-Hant", "ja", "ko", "es"] {
            let localized = try localizationEntries(languageCode: language)
            XCTAssertEqual(
                Set(localized.keys),
                Set(english.keys),
                "\(language) must contain exactly the English catalog keys"
            )
        }
    }

    func testRuntimeLookupUsesTheRequestedLanguage() {
        XCTAssertEqual(L10n.string("settings.title", language: .english), "Settings")
        XCTAssertEqual(L10n.string("settings.title", language: .simplifiedChinese), "设置")
        XCTAssertEqual(L10n.string("settings.title", language: .japanese), "設定")
    }

    func testLocalizedViewContentIsRecomputedAfterLanguageChanges() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Chat/Views/ChatView.swift"
            ),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Auth/Views/ModelProviderSettingsView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(chatSource.contains("static var defaults"))
        XCTAssertTrue(
            settingsSource.contains(
                "SettingsSidebar(selection: $selection, language: languageStore.language)"
            )
        )
        XCTAssertTrue(settingsSource.contains("let language: AppLanguage"))
        XCTAssertTrue(chatSource.contains(".lineLimit(3)"))
    }

    func testEveryReferencedLocalizationKeyExistsInTheCatalog() throws {
        let english = try localizationEntries(languageCode: "en")
        let source = try productionSwiftSource()
        let expression = try NSRegularExpression(
            pattern: #"L10n\.(?:string|format)\(\s*\"([^\"]+)\""#
        )
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let referencedKeys = Set<String>(expression.matches(in: source, range: range).compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[keyRange])
        })

        XCTAssertFalse(referencedKeys.isEmpty)
        XCTAssertEqual(referencedKeys.subtracting(english.keys), Set<String>())
    }

    func testLocalizedFormatPlaceholdersMatchEnglish() throws {
        let english = try localizationEntries(languageCode: "en")
        let expression = try NSRegularExpression(pattern: #"%(?:@|ld|%)"#)

        for language in ["zh-Hans", "zh-Hant", "ja", "ko", "es"] {
            let localized = try localizationEntries(languageCode: language)
            for (key, englishValue) in english {
                XCTAssertEqual(
                    placeholders(in: localized[key] ?? "", using: expression),
                    placeholders(in: englishValue, using: expression),
                    "\(language).lproj has incompatible placeholders for \(key)"
                )
            }
        }
    }

    func testProductionSwiftDoesNotContainHardcodedCJKUserFacingStrings() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appendingPathComponent("PiWork")
        let files = try FileManager.default.subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") && $0 != "Core/UI/AppLanguage.swift" }
        let expression = try NSRegularExpression(
            pattern: #"\"[^\"\n]*[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}][^\"\n]*\""#
        )
        var violations: [String] = []

        for relativePath in files {
            let source = try String(
                contentsOf: sourceRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            if expression.firstMatch(in: source, range: range) != nil {
                violations.append(relativePath)
            }
        }

        XCTAssertEqual(violations, [], "Move user-facing text into localization resources")
    }

    private func localizationEntries(languageCode: String) throws -> [String: String] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot
            .appendingPathComponent("PiWork/Resources/\(languageCode).lproj")
            .appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try XCTUnwrap(propertyList as? [String: String])
    }

    private func productionSwiftSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appendingPathComponent("PiWork")
        return try FileManager.default.subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") }
            .map {
                try String(
                    contentsOf: sourceRoot.appendingPathComponent($0),
                    encoding: .utf8
                )
            }
            .joined(separator: "\n")
    }

    private func placeholders(
        in value: String,
        using expression: NSRegularExpression
    ) -> [String] {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let placeholderRange = Range(match.range, in: value) else { return nil }
            return String(value[placeholderRange])
        }
    }
}
