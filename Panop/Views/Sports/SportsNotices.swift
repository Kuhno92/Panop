import PanopSports
import SwiftUI

/// What the hub says when there is no key yet: what it is, and where to put the key.
struct SportsNoKeyView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "sportscourt.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.green)
                Text("Sports")
                    .font(.largeTitle.bold())
                Text("""
                Today's football matches in the leagues and for the teams you follow, with scores, tables and line-ups, \
                and a button for the channel of your playlist that shows the match.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                Text("""
                It uses your own free account at sportapi.ai: get a key there and enter it in Settings, in the Sports \
                section. The free plan allows 2,000 requests a day, which is plenty.
                """)
                .multilineTextAlignment(.center)
                .font(.callout)
                NavigationLink {
                    SportsKeySettingsView()
                } label: {
                    Label("Enter the key", systemImage: "key.fill")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                #if !os(tvOS)
                .buttonStyle(.borderedProminent)
                #endif
                Link("Get a free key at sportapi.ai", destination: SportsConfig.website)
                    .font(.callout)
            }
            .padding(32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The first time with a working key: a step to pick leagues before anything can show.
struct SportsSetupPrompt: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "trophy.fill").font(.system(size: 48)).foregroundStyle(.yellow)
            Text("What do you follow?").font(.title.bold())
            Text("Pick the leagues you want to see, and, if you like, favourite teams. You can change them any time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: onStart) {
                Text("Choose leagues").font(.headline).padding(.horizontal, 12)
            }
            #if !os(tvOS)
            .buttonStyle(.borderedProminent)
            #endif
        }
        .padding(32)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A line at the top of the hub about the state of the data: the day's limit, a refused key, no connection.
struct SportsNoticeBanner: View {
    let notice: SportsHubModel.Notice
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
            if case .offline = notice {
                Button("Retry", action: onRetry).font(.subheadline.weight(.semibold))
            }
            if case .keyRefused = notice {
                NavigationLink("Key") { SportsKeySettingsView() }.font(.subheadline.weight(.semibold))
            }
        }
        .padding(12)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch notice {
        case .limitReached: "gauge.with.dots.needle.100percent"
        case .keyRefused: "key.slash"
        case .offline: "wifi.slash"
        case .unreadable: "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch notice {
        case .offline: .gray
        default: .orange
        }
    }

    private var text: String {
        switch notice {
        case let .limitReached(resetsAt):
            resetsAt.map {
                String(
                    localized: "The day's requests are used up. Scores update again at \($0.formatted(date: .omitted, time: .shortened))."
                )
            } ?? String(localized: "The day's requests are used up. Scores update again after the reset.")
        case .keyRefused:
            String(localized: "sportapi.ai did not accept the key.")
        case let .offline(since):
            since
                .map {
                    String(
                        localized: "Offline. Showing what was loaded at \($0.formatted(date: .omitted, time: .shortened))."
                    )
                }
                ?? String(localized: "Offline. The service could not be reached.")
        case .unreadable:
            String(localized: "The reply from sportapi.ai could not be read.")
        }
    }
}

/// Where the first rows will be, so the screen does not jump when they arrive.
struct SportsSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 28).frame(height: 210)
            ForEach(0 ..< 5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16).frame(height: 68)
            }
        }
        .foregroundStyle(.quaternary)
        .opacity(dim && !reduceMotion ? 0.55 : 1)
        .padding(.horizontal)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityHidden(true)
    }
}

/// A day with nothing of what the person follows.
struct SportsEmptyDay: View {
    let day: SportsHubModel.Day
    let hasSelection: Bool
    var onChange: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock").font(.largeTitle).foregroundStyle(.secondary)
            Text(day == .today ? "No matches today" : "No matches tomorrow").font(.title3.bold())
            Text("Nothing is on in the leagues and for the teams you follow.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Change leagues and teams", action: onChange)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
