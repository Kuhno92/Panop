import PanopCore
import SwiftUI

/// The "i" button: opens what the player knows about this stream, for a person who wonders where it comes from
/// and whether it goes through the VPN. While it is open the controls stay up.
struct StreamDetailsButton: View {
    let model: PlayerModel
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle")
            #if os(tvOS)
                .font(.title3)
            #else
                .font(.title2)
            #endif
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel("Stream details")
        .accessibilityIdentifier("playerDetails")
        .onChange(of: showing) { _, now in model.holdControls(now, reason: "details") }
        #if os(tvOS)
            .fullScreenCover(isPresented: $showing) { StreamDetailsView(model: model) }
        #else
            .sheet(isPresented: $showing) { StreamDetailsView(model: model) }
        #endif
    }
}

struct StreamDetailsView: View {
    let model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var lookup: [String]?
    @State private var looking = false

    private var host: String? {
        model.currentAddress.flatMap { URL(string: $0)?.host }
    }

    private var sections: [StreamDetailSection] {
        StreamDetails.sections(for: model, lookup: lookup)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row in
                            LabeledContent(row.label) {
                                Text(row.value)
                                    .multilineTextAlignment(.trailing)
                                #if !os(tvOS)
                                    .textSelection(.enabled)
                                #endif
                            }
                            #if os(tvOS)
                            .focusable()
                            #endif
                        }
                    }
                }
                if let host, host.contains(where: \.isLetter), !host.contains(":") {
                    Section {
                        Button {
                            looking = true
                            Task {
                                let found = await Task.detached { StreamDetails.resolve(host) }.value
                                lookup = found
                                looking = false
                            }
                        } label: {
                            HStack {
                                Text("Look up the address on this device")
                                if looking {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(looking)
                    } footer: {
                        Text("""
                        Asks this device's own resolver, outside any VPN, where the name leads. It shows whether a \
                        name such as a router's is on your local network.
                        """)
                    }
                }
            }
            .navigationTitle("Stream details")
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: StreamDetails.text(sections)) {
                            Label("Copy", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }
}
