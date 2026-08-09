import Foundation
import Combine

enum PiPackageType: String, CaseIterable, Codable {
    case extensionPackage = "extension"
    case skill
    case prompt
    case theme
}

struct PiPackageItem: Codable, Equatable, Identifiable {
    let name: String
    let summary: String
    let author: String
    let monthlyDownloads: Int
    let published: String?
    let types: [PiPackageType]
    let keywords: [String]

    init(
        name: String,
        summary: String,
        author: String,
        monthlyDownloads: Int,
        published: String?,
        types: [PiPackageType],
        keywords: [String] = []
    ) {
        self.name = name
        self.summary = summary
        self.author = author
        self.monthlyDownloads = monthlyDownloads
        self.published = published
        self.types = types
        self.keywords = keywords
    }

    var id: String { name }

    var pageURL: URL? {
        guard let path = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://pi.dev/packages/\(path)")
    }

    var packageSource: String { "npm:\(name)" }

    var installCommand: String { "pi install \(packageSource)" }

    var extensionCategory: PiExtensionCategory {
        PiExtensionCategory.classify(keywords: keywords)
    }
}

enum PiExtensionCategory: String, CaseIterable, Codable {
    case all
    case agents
    case developerTools
    case integrations
    case security
    case interface
    case memoryAndContext
    case other

    var title: String {
        switch self {
        case .all: return L10n.string("extensions.category.all_extensions")
        case .agents: return L10n.string("extensions.category.agents")
        case .developerTools: return L10n.string("extensions.category.developer_tools")
        case .integrations: return L10n.string("extensions.category.integrations")
        case .security: return L10n.string("extensions.category.security")
        case .interface: return L10n.string("extensions.category.interface")
        case .memoryAndContext: return L10n.string("extensions.category.memory_context")
        case .other: return L10n.string("extensions.category.other")
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .agents: return "person.2"
        case .developerTools: return "hammer"
        case .integrations: return "link"
        case .security: return "lock.shield"
        case .interface: return "macwindow"
        case .memoryAndContext: return "brain.head.profile"
        case .other: return "ellipsis.circle"
        }
    }

    func includes(_ item: PiPackageItem) -> Bool {
        self == .all || item.extensionCategory == self
    }

    static func classify(keywords: [String]) -> PiExtensionCategory {
        let keywords = Set(keywords.map { $0.lowercased() })
        var bestCategory = PiExtensionCategory.other
        var bestScore = 0
        for category in classificationOrder {
            let score = keywords.intersection(category.keywords).count
            if score > bestScore {
                bestCategory = category
                bestScore = score
            }
        }
        return bestCategory
    }

    private static let classificationOrder: [PiExtensionCategory] = [
        .security,
        .agents,
        .developerTools,
        .integrations,
        .interface,
        .memoryAndContext
    ]

    private var keywords: Set<String> {
        switch self {
        case .all, .other:
            return []
        case .agents:
            return [
                "agent", "agents", "subagent", "subagents", "autonomous",
                "automation", "orchestration", "task-orchestration",
                "spec-orchestration", "workflows", "swarm", "goal", "planning",
                "task-planning", "agent-loop", "background-tasks", "task-manager",
                "delegate"
            ]
        case .developerTools:
            return [
                "developer-tools", "code-review", "code-quality", "refactor", "linter",
                "lint", "lsp", "language-server-protocol", "diagnostics", "code-action",
                "structural-search", "structural-analysis", "code-map", "hashline",
                "apply-patch", "grep", "fuzzy-search", "type-coverage"
            ]
        case .integrations:
            return [
                "mcp", "model-context-protocol", "web-search", "web-fetch", "fetch",
                "scraping", "web-scraping", "browser-automation", "telegram", "atlassian",
                "jira", "confluence", "provider", "proxy", "cursor-sdk", "llama-cpp",
                "litellm", "ollama", "deepseek"
            ]
        case .security:
            return [
                "security", "audit", "permissions", "policy", "access-control",
                "authorization", "sandbox", "secret-scanning", "content-scanner"
            ]
        case .interface:
            return [
                "tui", "statusline", "status-bar", "footer", "powerline", "overlay",
                "interactive", "form", "voice", "dictation", "ask_user"
            ]
        case .memoryAndContext:
            return [
                "memory", "persistent-memory", "session-search", "session-history",
                "compaction", "context-fencing", "goosedump", "memory-aging"
            ]
        }
    }
}

struct ExtensionsCatalogRequest: Hashable {
    let query: String

    init(query: String = "") {
        self.query = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var isDefault: Bool { query.isEmpty }
}

struct ExtensionsCatalogPageParser {
    func parse(_ data: Data) throws -> [PiPackageItem] {
        guard let html = String(data: data, encoding: .utf8) else {
            throw ExtensionsCatalogParsingError.invalidEncoding
        }

        let articleExpression = try NSRegularExpression(
            pattern: #"<article\b[^>]*data-package-card="true"[^>]*>[\s\S]*?</article>"#,
            options: .caseInsensitive
        )
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seenNames: Set<String> = []
        var items: [PiPackageItem] = []

        for match in articleExpression.matches(in: html, range: range) {
            guard let articleRange = Range(match.range, in: html) else { continue }
            let article = String(html[articleRange])
            guard
                let openingTagEnd = article.firstIndex(of: ">"),
                let name = attribute(
                    "data-package-name",
                    in: String(article[...openingTagEnd])
                )
            else { continue }

            let rawTypes = attribute(
                "data-package-types",
                in: String(article[...openingTagEnd])
            ) ?? ""
            let types = rawTypes
                .split(whereSeparator: \Character.isWhitespace)
                .compactMap { PiPackageType(rawValue: String($0)) }
            guard types.contains(.extensionPackage) else { continue }
            let metadata = metaValues(in: article)
            let decodedName = decodeHTML(name)
            guard seenNames.insert(decodedName).inserted else { continue }
            let summary = classText("packages-desc", in: article) ?? ""
            let author = metadata.first ?? L10n.string("extensions.unknown_author")

            items.append(
                PiPackageItem(
                    name: decodedName,
                    summary: summary,
                    author: author,
                    monthlyDownloads: Int(
                        attribute(
                            "data-package-downloads",
                            in: String(article[...openingTagEnd])
                        ) ?? ""
                    ) ?? 0,
                    published: metadata.count > 2 ? metadata[2] : nil,
                    types: types,
                    keywords: keywords(
                        from: attribute(
                            "data-package-search",
                            in: String(article[...openingTagEnd])
                        ),
                        name: decodedName,
                        summary: summary,
                        author: author,
                        rawTypes: rawTypes
                    )
                )
            )
        }

        guard !items.isEmpty else { throw ExtensionsCatalogParsingError.noPackages }
        return items
    }

    private func attribute(_ name: String, in html: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*\"([^\"]*)\"",
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard
            let match = expression.firstMatch(in: html, range: range),
            let valueRange = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[valueRange])
    }

    private func classText(_ className: String, in html: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"<[^>]+class="[^"]*\#(className)[^"]*"[^>]*>([\s\S]*?)</[^>]+>"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard
            let match = expression.firstMatch(in: html, range: range),
            let valueRange = Range(match.range(at: 1), in: html)
        else { return nil }
        return normalizedText(String(html[valueRange]))
    }

    private func metaValues(in html: String) -> [String] {
        guard
            let metadata = classHTML("packages-meta", in: html),
            let expression = try? NSRegularExpression(
                pattern: #"<span\b[^>]*>([\s\S]*?)</span>"#,
                options: .caseInsensitive
            )
        else { return [] }
        let range = NSRange(metadata.startIndex..<metadata.endIndex, in: metadata)
        return expression.matches(in: metadata, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: metadata) else { return nil }
            return normalizedText(String(metadata[valueRange]))
        }
    }

    private func classHTML(_ className: String, in html: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"<div\b[^>]*class="[^"]*\#(className)[^"]*"[^>]*>([\s\S]*?)</div>"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard
            let match = expression.firstMatch(in: html, range: range),
            let valueRange = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[valueRange])
    }

    private func normalizedText(_ html: String) -> String {
        let withoutTags = (try? NSRegularExpression(pattern: #"<[^>]+>"#))?
            .stringByReplacingMatches(
                in: html,
                range: NSRange(html.startIndex..<html.endIndex, in: html),
                withTemplate: ""
            ) ?? html
        return decodeHTML(withoutTags)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func keywords(
        from rawSearchText: String?,
        name: String,
        summary: String,
        author: String,
        rawTypes: String
    ) -> [String] {
        guard let rawSearchText else { return [] }
        let searchText = normalizedMetadataText(decodeHTML(rawSearchText))
        let prefix = normalizedMetadataText(
            [name, summary, author, rawTypes].joined(separator: " ")
        )
        guard searchText.hasPrefix(prefix) else { return [] }
        return searchText
            .dropFirst(prefix.count)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
    }

    private func normalizedMetadataText(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func decodeHTML(_ text: String) -> String {
        [
            ("&nbsp;", " "),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&#x27;", "'"),
            ("&apos;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&")
        ].reduce(text) { result, entity in
            result.replacingOccurrences(of: entity.0, with: entity.1)
        }
    }
}

struct ExtensionsCatalogFilter {
    let query: String
    let category: PiExtensionCategory

    func apply(to items: [PiPackageItem]) -> [PiPackageItem] {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)

        return items.filter { item in
            guard category.includes(item) else { return false }
            guard !terms.isEmpty else { return true }
            let searchableText = [
                item.name,
                item.summary,
                item.author,
                item.keywords.joined(separator: " ")
            ]
                .joined(separator: " ")
                .lowercased()
            return terms.allSatisfy { searchableText.contains($0) }
        }
    }
}

struct ExtensionsCatalogCachePolicy {
    let maxAge: TimeInterval

    init(maxAge: TimeInterval = 6 * 60 * 60) {
        self.maxAge = maxAge
    }

    func shouldRefresh(_ snapshot: ExtensionsCatalogSnapshot?, now: Date) -> Bool {
        guard let snapshot, !snapshot.items.isEmpty else { return true }
        return now.timeIntervalSince(snapshot.fetchedAt) >= maxAge
    }
}

struct ExtensionsCatalogSnapshot: Codable, Equatable {
    let items: [PiPackageItem]
    let fetchedAt: Date
}

enum ExtensionsCatalogParsingError: LocalizedError {
    case invalidEncoding
    case noPackages

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return L10n.string("extensions.error.unreadable_response")
        case .noPackages:
            return L10n.string("extensions.error.catalog_parse")
        }
    }
}

protocol ExtensionsCatalogFetching {
    func fetchPackages(
        for request: ExtensionsCatalogRequest,
        ignoringCache: Bool
    ) async throws -> [PiPackageItem]
}

protocol ExtensionsCatalogCaching {
    func load() throws -> ExtensionsCatalogSnapshot?
    func save(_ snapshot: ExtensionsCatalogSnapshot) throws
}

struct RemoteExtensionsCatalogClient: ExtensionsCatalogFetching {
    let session: URLSession
    let parser: ExtensionsCatalogPageParser

    init(
        session: URLSession = .shared,
        parser: ExtensionsCatalogPageParser = ExtensionsCatalogPageParser()
    ) {
        self.session = session
        self.parser = parser
    }

    func fetchPackages(
        for request: ExtensionsCatalogRequest,
        ignoringCache: Bool
    ) async throws -> [PiPackageItem] {
        guard let url = Self.catalogURL(for: request) else {
            throw ExtensionsCatalogNetworkError.invalidURL
        }
        var urlRequest = URLRequest(
            url: url,
            cachePolicy: ignoringCache ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy,
            timeoutInterval: 30
        )
        urlRequest.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: urlRequest)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw ExtensionsCatalogNetworkError.invalidResponse
        }
        return try parser.parse(data)
    }

    static func catalogURL(for request: ExtensionsCatalogRequest) -> URL? {
        var components = URLComponents(string: "https://pi.dev/packages")
        var queryItems: [URLQueryItem] = []
        if !request.query.isEmpty {
            queryItems.append(URLQueryItem(name: "name", value: request.query))
        }
        queryItems.append(URLQueryItem(name: "type", value: PiPackageType.extensionPackage.rawValue))
        queryItems.append(URLQueryItem(name: "sort", value: "downloads"))
        components?.queryItems = queryItems
        return components?.url
    }
}

struct DiskExtensionsCatalogCache: ExtensionsCatalogCaching {
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> ExtensionsCatalogSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(
            ExtensionsCatalogSnapshot.self,
            from: Data(contentsOf: fileURL)
        )
    }

    func save(_ snapshot: ExtensionsCatalogSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pi-work/Cache/extensions-catalog-v2.json")
    }
}

@MainActor
final class ExtensionsCatalogStore: ObservableObject {
    @Published private(set) var items: [PiPackageItem] = []
    @Published private(set) var activeRequest = ExtensionsCatalogRequest()
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private let client: ExtensionsCatalogFetching
    private let cache: ExtensionsCatalogCaching
    private let cachePolicy: ExtensionsCatalogCachePolicy
    private var snapshots: [ExtensionsCatalogRequest: ExtensionsCatalogSnapshot] = [:]
    private var didReadDiskCache = false
    private var activeLoadID: UUID?

    init(
        client: ExtensionsCatalogFetching = RemoteExtensionsCatalogClient(),
        cache: ExtensionsCatalogCaching = DiskExtensionsCatalogCache(),
        cachePolicy: ExtensionsCatalogCachePolicy = ExtensionsCatalogCachePolicy()
    ) {
        self.client = client
        self.cache = cache
        self.cachePolicy = cachePolicy
    }

    func load(_ request: ExtensionsCatalogRequest = .init(), now: Date = Date()) async {
        activeRequest = request
        errorMessage = nil

        if request.isDefault, !didReadDiskCache {
            didReadDiskCache = true
            if let snapshot = try? cache.load() {
                snapshots[request] = snapshot
                apply(snapshot, for: request)
                guard cachePolicy.shouldRefresh(snapshot, now: now) else { return }
            }
        } else if let snapshot = snapshots[request] {
            apply(snapshot, for: request)
            return
        }

        if snapshots[request] == nil {
            items = []
            lastUpdated = nil
        }
        await fetch(request, ignoringCache: false, now: now, isRefresh: false)
    }

    func refresh(
        _ request: ExtensionsCatalogRequest = .init(),
        now: Date = Date()
    ) async {
        activeRequest = request
        errorMessage = nil
        await fetch(request, ignoringCache: true, now: now, isRefresh: true)
    }

    private func fetch(
        _ request: ExtensionsCatalogRequest,
        ignoringCache: Bool,
        now: Date,
        isRefresh: Bool
    ) async {
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = !isRefresh
        isRefreshing = isRefresh
        defer {
            if activeLoadID == loadID {
                isLoading = false
                isRefreshing = false
            }
        }

        do {
            let fetchedItems = try await client.fetchPackages(
                for: request,
                ignoringCache: ignoringCache
            )
            guard activeLoadID == loadID else { return }
            guard !fetchedItems.isEmpty else {
                throw ExtensionsCatalogParsingError.noPackages
            }

            let snapshot = ExtensionsCatalogSnapshot(items: fetchedItems, fetchedAt: now)
            snapshots[request] = snapshot
            if request.isDefault { try? cache.save(snapshot) }
            apply(snapshot, for: request)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadID == loadID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func apply(
        _ snapshot: ExtensionsCatalogSnapshot,
        for request: ExtensionsCatalogRequest
    ) {
        guard activeRequest == request else { return }
        items = snapshot.items
        lastUpdated = snapshot.fetchedAt
    }
}

enum ExtensionsCatalogNetworkError: LocalizedError {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.string("extensions.error.invalid_url")
        case .invalidResponse:
            return L10n.string("extensions.error.unavailable")
        }
    }
}
