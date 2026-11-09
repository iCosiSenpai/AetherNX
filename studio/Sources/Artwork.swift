import AppKit
import Foundation
import Observation

/// What the internet knows about one game: which pictures were saved, and a few facts for the game's page.
struct OnlineArt: Codable, Equatable {
    /// nil when no service had the game.
    var source: String?
    var publisher: String?
    var releaseDate: String?
    var hasIcon = false
    var hasBanner = false
    var hasCover = false
    var fetched = Date()
}

/// Game pictures from the internet, kept on disk. A Switch game's square icon and wide banner come from nlib.cc by its
/// title ID; a game nlib does not list (Switch 2 games among them) gets its box art from Wikipedia, looked up by name.
/// The icon in the game's own files, which a build extracts, is the fallback. Only the title ID or the name is sent.
@MainActor
@Observable
final class ArtworkStore {
    private(set) var art: [String: OnlineArt] = [:]
    @ObservationIgnored private var queue: [(titleId: String, name: String)] = []
    @ObservationIgnored private var queued: Set<String> = []
    @ObservationIgnored private var isWorking = false
    @ObservationIgnored let directory: URL

    /// A game no service had is asked again after this long.
    private static let retryAfter: TimeInterval = 7 * 24 * 3600

    init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "io.github.icosisenpai.aethernx").appending(path: "Artwork")
        let decoder = JSONDecoder()
        for folder in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            if let data = try? Data(contentsOf: folder.appending(path: "art.json")), let entry = try? decoder.decode(OnlineArt.self, from: data) {
                art[folder.lastPathComponent] = entry
            }
        }
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: Pref.downloadArtwork) }

    // MARK: Pictures for the views

    /// The square picture: the online icon, else the online box art, else the icon from the game's files.
    func icon(for game: Game) -> String? {
        if Self.isEnabled, let id = game.titleId, let entry = art[id] {
            if entry.hasIcon { return file(id, "icon.jpg") }
            if entry.hasCover { return file(id, "cover.jpg") }
        }
        return game.icon
    }

    /// A wide picture for backgrounds, when a service has one.
    func banner(for game: Game) -> String? {
        guard Self.isEnabled, let id = game.titleId, art[id]?.hasBanner == true else { return nil }
        return file(id, "banner.jpg")
    }

    /// What Console Mode and the game's page blur behind the game: the banner, else the icon.
    func backdrop(for game: Game) -> String? { banner(for: game) ?? icon(for: game) }

    func info(for game: Game) -> OnlineArt? {
        guard Self.isEnabled, let id = game.titleId, let entry = art[id], entry.source != nil else { return nil }
        return entry
    }

    private func file(_ id: String, _ name: String) -> String { directory.appending(path: id).appending(path: name).path }

    // MARK: Fetching

    /// Looks the game up once (again a week after a miss); the views ask for every game they show.
    func request(_ game: Game) {
        guard Self.isEnabled, game.isBuildable, let id = game.titleId, !queued.contains(id) else { return }
        if let entry = art[id], entry.source != nil || Date().timeIntervalSince(entry.fetched) < Self.retryAfter { return }
        queued.insert(id)
        queue.append((id, game.name))
        guard !isWorking else { return }
        isWorking = true
        Task {
            while !queue.isEmpty {
                let next = queue.removeFirst()
                let folder = directory.appending(path: next.titleId)
                if let entry = await Self.fetch(titleId: next.titleId, name: next.name, into: folder) {
                    if let data = try? JSONEncoder().encode(entry) { try? data.write(to: folder.appending(path: "art.json")) }
                    IconCache.forget(prefix: folder.path)
                    art[next.titleId] = entry
                }
            }
            isWorking = false
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
        IconCache.forget(prefix: directory.path)
        art = [:]
        queued = []
    }

    /// nil when the services could not be reached: nothing is recorded and the game is asked again next time.
    nonisolated static func fetch(titleId: String, name: String, into folder: URL) async -> OnlineArt? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var entry = OnlineArt()
        var reached = false
        // nlib lists Switch games, whose base title IDs start with 01
        if titleId.hasPrefix("01"), let base = URL(string: "https://api.nlib.cc/nx/\(titleId)") {
            switch await json(base) {
            case .found(let info):
                reached = true
                entry.source = "nlib.cc"
                entry.publisher = (info["publisher"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                entry.releaseDate = info["releaseDate"] as? String
                entry.hasIcon = await download(base.appending(path: "icon/512/512"), to: folder.appending(path: "icon.jpg"))
                entry.hasBanner = await download(base.appending(path: "banner/720p"), to: folder.appending(path: "banner.jpg"))
            case .missing: reached = true
            case .unreachable: break
            }
        }
        if !entry.hasIcon {
            switch await wikipediaCover(for: name) {
            case .found(let url):
                reached = true
                if await download(url, to: folder.appending(path: "cover.jpg")) {
                    entry.hasCover = true
                    entry.source = entry.source ?? "Wikipedia"
                }
            case .missing: reached = true
            case .unreachable: break
            }
        }
        return reached ? entry : nil
    }

    private enum Lookup<T> { case found(T), missing, unreachable }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        configuration.httpAdditionalHeaders = ["User-Agent": "AetherNXStudio/\(version) (+\(Links.repository.absoluteString))"]
        return URLSession(configuration: configuration)
    }()

    private nonisolated static func json(_ url: URL) async -> Lookup<[String: Any]> {
        guard let (data, response) = try? await session.data(from: url), let http = response as? HTTPURLResponse else { return .unreachable }
        guard http.statusCode == 200 else { return http.statusCode == 404 ? .missing : .unreachable }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .missing }
        return .found(object)
    }

    /// Saves a picture when the answer is one; the file is written whole or not at all.
    private nonisolated static func download(_ url: URL, to file: URL) async -> Bool {
        guard let (data, response) = try? await session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200,
              data.count > 512, NSImage(data: data) != nil else { return false }
        return (try? data.write(to: file, options: .atomic)) != nil
    }

    /// The image on the game's English Wikipedia article (the box art). The page is the one named as the game, or the first
    /// search result whose title is the game's name once punctuation and case are set aside, so a series' other game never stands in.
    private nonisolated static func wikipediaCover(for name: String) async -> Lookup<URL> {
        let title = name.replacingOccurrences(of: #"[™®©]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let wanted = normalized(title)
        guard !wanted.isEmpty else { return .missing }
        var exact = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        exact.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"), .init(name: "redirects", value: "1"),
            .init(name: "titles", value: "\(title)|\(title) (video game)"),
            .init(name: "prop", value: "pageimages"), .init(name: "piprop", value: "original"), .init(name: "pilicense", value: "any"),
        ]
        var search = exact
        search.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"),
            .init(name: "generator", value: "search"), .init(name: "gsrsearch", value: "\(title) video game"), .init(name: "gsrlimit", value: "5"),
            .init(name: "prop", value: "pageimages"), .init(name: "piprop", value: "original"), .init(name: "pilicense", value: "any"),
        ]
        var reached = false
        for components in [exact, search] {
            guard let url = components.url else { continue }
            switch await json(url) {
            case .found(let object):
                reached = true
                let pages = ((object["query"] as? [String: Any])?["pages"] as? [String: Any])?.values.compactMap { $0 as? [String: Any] } ?? []
                let sorted = pages.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
                for page in sorted {
                    guard let pageTitle = page["title"] as? String else { continue }
                    let candidate = normalized(pageTitle.replacingOccurrences(of: " (video game)", with: ""))
                    guard candidate == wanted, let source = (page["original"] as? [String: Any])?["source"] as? String,
                          let image = URL(string: source) else { continue }
                    return .found(image)
                }
            case .missing: reached = true
            case .unreachable: break
            }
        }
        return reached ? .missing : .unreachable
    }

    private nonisolated static func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }
}
