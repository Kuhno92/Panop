import SwiftUI

/// What Panop is, which version this is, and who it owes thanks to.
struct AboutView: View {
    /// `1.2 (45)`, as the app reports itself.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    /// Where the source is, as the licence asks.
    static let sourceCode = URL(string: "https://github.com/Kuhno92/Panop")

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    AppLogo(size: 96)
                    Text("Panop").font(.largeTitle.bold())
                    Text("Version \(Self.version)").foregroundStyle(.secondary)
                    Text("A player for your own TV, movies and series.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                credit("Nuvio", "for what a modern, rail-based home screen can feel like.")
                credit("Lume", "whose approach to long-running live streams led to Panop's LumeEngine player.")
                credit("IPTV Deck", "for showing how much a guide-first live TV app can do.")
            } header: {
                Text("Thanks to")
            } footer: {
                Text("Their names belong to their authors. Panop is not affiliated with or endorsed by any of them.")
            }
            Section {
                if let source = Self.sourceCode {
                    Link(destination: source) {
                        Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            } footer: {
                Text("Panop ships no content. It only plays the sources you add yourself.")
            }
            Section {
                Text("Movie, TV and anime data from Simkl")
            } header: {
                Text("Data")
            } footer: {
                Text("""
                Panop is free software under the GNU General Public Licence, version 3. \
                The parts it is built from are listed in THIRD-PARTY-NOTICES.md.
                """)
            }
        }
        .formStyle(.grouped)
        .pageBackdrop()
        .navigationTitle("About Panop")
    }

    private func credit(_ name: String, _ reason: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.headline)
            Text(reason).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
