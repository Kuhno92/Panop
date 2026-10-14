import PanopSports
import SwiftUI

/// Where the person picks the leagues they follow and, if they like, favourite teams. The first time it is the hub's
/// setup (leagues, then teams); later it is the same screen to change them. Each choice is kept as it is made, and
/// travels to the person's other devices with the rest of their iCloud data.
struct SportsSelectionView: View {
    enum Step {
        case leagues, teams
    }

    /// True the first time: "Next" and "Done" lead on, and finishing marks the setup as done.
    var isSetup = false
    var onFinish: () -> Void = {}

    @Environment(SportsSyncStore.self) private var sync
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.sportsFeed) private var feed
    @State private var step: Step = .leagues
    @State private var groups: [LeagueGroup] = []
    @State private var phase: Phase = .loading
    @State private var query = ""
    @State private var candidates: [TeamCandidates] = []
    @State private var loadingTeams = false

    private enum Phase: Equatable {
        case loading, ready, failed(String)
    }

    private struct TeamCandidates: Identifiable {
        var league: SportsLeagueChoice
        var teams: [TeamRef]

        var id: Int {
            league.id
        }
    }

    private var profile: String {
        profiles.currentID
    }

    var body: some View {
        // Read here so the screen follows the choices as they are made, and as they arrive from another device.
        let chosenLeagues = Set(sync.leagues(profile: profile).map(\.id))
        let chosenTeams = Set(sync.teams(profile: profile).map(\.id))
        // A declaration, because a view builder takes no plain statement; it makes the screen follow the choices.
        // swiftlint:disable:next redundant_discardable_let
        let _ = sync.revision
        Group {
            switch step {
            case .leagues: leaguePicker(chosen: chosenLeagues)
            case .teams: teamPicker(chosen: chosenTeams)
            }
        }
        .navigationTitle(step == .leagues ? Text("Leagues") : Text("Favourite teams"))
        #if !os(tvOS)
            .searchable(text: $query, prompt: step == .leagues ? Text("Search leagues") : Text("Search teams"))
        #endif
            .task { await loadLeagues() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    primaryButton(hasLeagues: !chosenLeagues.isEmpty, hasTeams: !chosenTeams.isEmpty)
                }
            }
    }

    // MARK: - Leagues

    private func leaguePicker(chosen: Set<Int>) -> some View {
        List {
            switch phase {
            case .loading:
                HStack { ProgressView(); Text("Loading leagues…").foregroundStyle(.secondary) }
            case let .failed(text):
                Text(text).foregroundStyle(.secondary)
                Button("Try again") { Task { await loadLeagues(force: true) } }
            case .ready:
                if query.isEmpty, !popular.isEmpty {
                    Section("Popular") {
                        ForEach(popular) { league in leagueRow(league.choice, chosen: chosen.contains(league.id)) }
                    }
                }
                ForEach(filteredGroups) { group in
                    Section(group.country) {
                        ForEach(group.leagues) { league in
                            leagueRow(
                                SportsLeagueChoice(id: league.id, name: league.name, country: group.country),
                                chosen: chosen.contains(league.id)
                            )
                        }
                    }
                }
            }
        }
        .pageBackdrop()
    }

    private func leagueRow(_ league: SportsLeagueChoice, chosen: Bool) -> some View {
        Button {
            sync.setLeague(league, chosen: !chosen, profile: profile)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(league.name)
                    if query.isEmpty == false || chosen {
                        Text(league.country).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chosen ? Color.green : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var filteredGroups: [LeagueGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            let leagues = group.leagues.filter {
                $0.name.localizedCaseInsensitiveContains(needle) || group.country
                    .localizedCaseInsensitiveContains(needle)
            }
            return leagues.isEmpty ? nil : LeagueGroup(country: group.country, leagues: leagues)
        }
    }

    private struct PopularLeague: Identifiable {
        var choice: SportsLeagueChoice

        var id: Int {
            choice.id
        }
    }

    /// The competitions most people look for, found by name.
    private var popular: [PopularLeague] {
        let wanted = [
            "premier league", "bundesliga", "la liga", "laliga", "serie a", "ligue 1", "champions league",
            "europa league", "eredivisie", "primeira liga", "major league soccer"
        ]
        var found: [PopularLeague] = []
        for group in groups {
            for league in group.leagues where wanted.contains(where: { league.name.lowercased().hasSuffix($0) }) {
                found.append(PopularLeague(choice: SportsLeagueChoice(
                    id: league.id,
                    name: league.name,
                    country: group.country
                )))
            }
        }
        return found
    }

    // MARK: - Teams

    private func teamPicker(chosen: Set<Int>) -> some View {
        List {
            if loadingTeams {
                HStack { ProgressView(); Text("Loading teams…").foregroundStyle(.secondary) }
            }
            ForEach(filteredCandidates) { entry in
                Section(entry.league.name) {
                    ForEach(entry.teams) { team in
                        let choice = SportsTeamChoice(
                            id: team.id, name: team.name, short: team.shortName, logo: team.logo,
                            leagueID: entry.league.id
                        )
                        Button {
                            sync.setTeam(choice, chosen: !chosen.contains(team.id), profile: profile)
                        } label: {
                            HStack(spacing: 12) {
                                TeamCrest(logo: team.logo, name: team.name, size: 30)
                                Text(team.name)
                                Spacer()
                                Image(systemName: chosen.contains(team.id) ? "star.fill" : "star")
                                    .foregroundStyle(chosen.contains(team.id) ? Color.yellow : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen.contains(team.id) ? .isSelected : [])
                    }
                }
            }
            if !loadingTeams, candidates.isEmpty {
                Text("Teams of leagues with a table show up here. Choose a league first.").foregroundStyle(.secondary)
            }
        }
        .pageBackdrop()
        .task { await loadTeams() }
    }

    private var filteredCandidates: [TeamCandidates] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return candidates }
        return candidates.compactMap { entry in
            let teams = entry.teams.filter { $0.name.localizedCaseInsensitiveContains(needle) }
            return teams.isEmpty ? nil : TeamCandidates(league: entry.league, teams: teams)
        }
    }

    // MARK: - Moving on

    @ViewBuilder
    private func primaryButton(hasLeagues: Bool, hasTeams: Bool) -> some View {
        switch step {
        case .leagues:
            if isSetup {
                Button("Next") {
                    query = ""
                    step = .teams
                }
                .disabled(!hasLeagues)
            } else {
                Button("Favourite teams") {
                    query = ""
                    step = .teams
                }
            }
        case .teams:
            Button("Done") {
                sync.setSetupDone(true, profile: profile)
                onFinish()
            }
        }
    }

    // MARK: - Data

    private func loadLeagues(force: Bool = false) async {
        guard let feed else {
            phase = .failed(String(localized: "Sports are not available."))
            return
        }
        if phase == .ready, !force {
            return
        }
        phase = .loading
        let result = await feed.leagues(force: force)
        if let value = result.value {
            groups = value
            phase = .ready
        } else {
            phase = .failed(failureText(result.error))
        }
    }

    /// The teams of each chosen league, from its table (which the hub reads too, so it costs nothing twice).
    private func loadTeams() async {
        guard let feed else { return }
        loadingTeams = true
        defer { loadingTeams = false }
        var found: [TeamCandidates] = []
        for league in sync.leagues(profile: profile) {
            let result = await feed.standings(league: league.id)
            let teams = (result.value ?? []).map(\.team).sorted { $0.name < $1.name }
            if !teams.isEmpty {
                found.append(TeamCandidates(league: league, teams: teams))
            }
        }
        candidates = found
    }

    private func failureText(_ error: SportsError?) -> String {
        switch error {
        case .unauthorized?: String(localized: "The key was not accepted. Check it in Settings.")
        case .dailyLimit?: String(localized: "The day's requests are used up. Try again after the reset.")
        default: String(localized: "The leagues could not be loaded. Check the connection and try again.")
        }
    }
}
