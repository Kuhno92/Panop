import Foundation
import PanopCore
import PanopDiscover

/// The plan a Simkl account is on. Custom lists are for PRO and VIP.
public enum SimklPlan: String, Sendable, Equatable, Codable {
    case free, pro, vip

    public var hasCustomLists: Bool {
        self != .free
    }
}

public struct SimklAccountInfo: Sendable, Equatable {
    public var id: Int
    public var plan: SimklPlan
}

/// One of a person's own lists, as the index of their lists describes it.
public struct SimklCustomListInfo: Sendable, Equatable {
    public var id: Int
    public var name: String
    /// `movies`, `tv`, `anime` or something that mixes them.
    public var mediaType: String
    public var itemCount: Int
}

public extension SimklClient {
    /// Who the token belongs to and what plan they are on.
    func account() async throws -> SimklAccountInfo {
        let data = try await get("/users/settings")
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["account"] as? [String: Any],
              let id = account["id"] as? Int
        else { throw SimklError.undecodable }
        let plan = (account["type"] as? String).flatMap(SimklPlan.init) ?? .free
        return SimklAccountInfo(id: id, plan: plan)
    }

    /// Simkl's own ranking of a kind of title, from its genre-browse endpoints (the real "Best on Netflix"),
    /// a few pages of sixty. A list that does not exist comes back as `null`, which is an empty list.
    ///
    /// - Parameter path: for example `tv/genres/all/all/all/netflix/all/rank`.
    func ranked(_ path: String, kind: MediaKind, pages: Int) async throws -> [SimklTitle] {
        var found: [SimklTitle] = []
        for page in 1 ... max(pages, 1) {
            let data = try await get("/" + path, query: [
                URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: "60")
            ])
            guard let titles = SimklFile.titles(from: data, kind: kind), !titles.isEmpty else { break }
            // The positions carry on from page to page, so the order is the ranking's.
            found += titles.map { var title = $0; title.position += (page - 1) * 60; return title }
            if titles.count < 60 {
                break
            }
        }
        return found
    }

    /// The person's own custom lists (a PRO or VIP feature). Throws `.premiumOnly` for a free account, whose
    /// answer is a successful-looking reply that holds a placeholder instead of lists.
    func customLists(userID: Int, limit: Int = 50) async throws -> [SimklCustomListInfo] {
        let data = try await get("/lists/user/\(userID)", query: [URLQueryItem(name: "limit", value: String(limit))])
        let root = try Self.object(data)
        guard let lists = root["lists"] as? [[String: Any]] else { throw SimklError.undecodable }
        return lists.compactMap { list in
            guard let id = list["id"] as? Int, let name = list["name"] as? String else { return nil }
            let counts = list["counts"] as? [String: Any]
            return SimklCustomListInfo(
                id: id, name: name, mediaType: (list["media_type"] as? String) ?? "",
                itemCount: (counts?["items"] as? Int) ?? 0
            )
        }
    }

    /// The films and series in one list, in the order its owner put them. Anime is left out.
    func customListItems(id: Int, limit: Int = 100) async throws -> [SimklTitle] {
        let data = try await get("/lists/\(id)", query: [URLQueryItem(name: "limit", value: String(limit))])
        let root = try Self.object(data)
        guard let items = root["items"] as? [[String: Any]] else { throw SimklError.undecodable }
        return items.enumerated().compactMap { index, item in
            switch item["type"] as? String {
            case "movie": SimklFile.title(from: item, kind: .movie, position: index)
            case "tv", "show": SimklFile.title(from: item, kind: .series, position: index)
            default: nil
            }
        }
    }

    /// A reply that is an object, and not the placeholder a free account gets in place of data.
    internal static func object(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SimklError.undecodable }
        if (root["error"] as? String) == "premium_only" {
            throw SimklError.premiumOnly
        }
        return root
    }
}

/// Builds the lists that need an account: Simkl's real rankings, and the person's own.
public enum SimklAccountLists {
    /// What is ranked, and where Simkl ranks it. The ids are the ones `SimklLists` uses for the same list made
    /// from the public files, which these replace when they are there. Only networks Simkl documents a name for
    /// are here: an unknown one is silently read as "all", which would be a wrong list under a right name.
    struct Spec {
        var id: String
        var kind: MediaKind
        var path: String
        var pages: Int
        var isHighlight = false
    }

    static let specs: [Spec] = [
        Spec(
            id: "network.Netflix",
            kind: .series,
            path: "tv/genres/all/all/all/netflix/all/rank",
            pages: 3,
            isHighlight: true
        ),
        Spec(id: "network.HBO", kind: .series, path: "tv/genres/all/all/all/hbo/all/rank", pages: 3),
        Spec(id: "network.Apple TV", kind: .series, path: "tv/genres/all/all/all/apple-tv/all/rank", pages: 3),
        Spec(id: "network.Prime Video", kind: .series, path: "tv/genres/all/all/all/prime-video/all/rank", pages: 3)
    ]
        + [("Action", "action"), ("Drama", "drama"), ("Comedy", "comedy"), ("Science Fiction", "science-fiction"),
           ("Thriller", "thriller"), ("Horror", "horror")].map {
            Spec(id: "genre.\($0.0)", kind: .movie, path: "movies/genres/\($0.1)/movies/all/all/rank", pages: 2)
        }
        + [2020, 2010, 2000, 1990].map {
            Spec(id: "decade.\($0)", kind: .movie, path: "movies/genres/all/movies/all/\($0)s/rank", pages: 2)
        }
        + [("Drama", "drama"), ("Comedy", "comedy"), ("Crime", "crime")].map {
            Spec(id: "genre.\($0.0)", kind: .series, path: "tv/genres/\($0.1)/all/all/all/all/rank", pages: 2)
        }

    /// Simkl's real rankings. A list that fails alone is left out; a login that is refused stops the lot.
    public static func ranked(client: SimklClient) async throws -> [CuratedList] {
        var lists: [CuratedList] = []
        for spec in specs {
            do {
                let titles = try await client.ranked(spec.path, kind: spec.kind, pages: spec.pages)
                let entries = SimklLists.entries(of: titles)
                if !entries.isEmpty {
                    lists.append(CuratedList(
                        id: spec.id,
                        kind: spec.kind,
                        isHighlight: spec.isHighlight,
                        entries: entries
                    ))
                }
            } catch SimklError.unauthorized {
                throw SimklError.unauthorized
            } catch let SimklError.rateLimited(wait) {
                throw SimklError.rateLimited(retryAfter: wait)
            } catch {
                continue
            }
        }
        return lists
    }

    /// The person's own lists, up to `maxLists`, each as a list of its own. Needs PRO or VIP, which is checked
    /// first so a free account costs one request. Returns nothing for a free account, and says so by the plan.
    public static func custom(
        client: SimklClient,
        maxLists: Int = 12
    ) async throws -> (plan: SimklPlan, lists: [CuratedList]) {
        let account = try await client.account()
        guard account.plan.hasCustomLists else { return (account.plan, []) }
        let infos: [SimklCustomListInfo]
        do {
            infos = try await client.customLists(userID: account.id)
        } catch SimklError.premiumOnly {
            return (.free, [])
        }
        var lists: [CuratedList] = []
        for info in infos.prefix(maxLists) where info.itemCount > 0 {
            guard let titles = try? await client.customListItems(id: info.id) else { continue }
            let entries = SimklLists.entries(of: titles)
            guard !entries.isEmpty else { continue }
            lists.append(CuratedList(
                id: "custom.\(info.id)", kind: kind(of: info, titles: titles), isHighlight: true, title: info.name,
                entries: entries
            ))
        }
        return (account.plan, lists)
    }

    /// What a list is mostly of, by what it says or else by what is in it.
    static func kind(of info: SimklCustomListInfo, titles: [SimklTitle]) -> MediaKind {
        switch info.mediaType {
        case "movies": .movie
        case "tv": .series
        default: titles.filter { $0.kind == .series }.count > titles.count / 2 ? .series : .movie
        }
    }

    /// Replaces a list made from the public files with Simkl's own ranking of the same, where there is one.
    public static func merging(_ base: [CuratedList], with better: [CuratedList]) -> [CuratedList] {
        var result = base.map { list in better.first { $0.id == list.id && $0.kind == list.kind } ?? list }
        for list in better where !result.contains(where: { $0.id == list.id && $0.kind == list.kind }) {
            result.append(list)
        }
        return result
    }
}
