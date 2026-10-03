import SwiftUI
import UniformTypeIdentifiers

/// The form for adding a playlist by M3U link, M3U file or Xtream login.
struct AddPlaylistView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case xtream = "Xtream login"
        case m3uURL = "M3U link"
        #if !os(tvOS)
            case m3uFile = "M3U file"
        #endif

        var id: String {
            rawValue
        }
    }

    @Environment(PlaylistLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var mode = Mode.xtream
    @State private var name = ""
    @State private var link = ""
    @State private var guideLink = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var pickedFile: URL?
    @State private var showingFilePicker = false
    @State private var liveOnly = false
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                #if !os(tvOS)
                .pickerStyle(.segmented)
                #endif
                TextField("Name (optional)", text: $name)
            }

            switch mode {
            case .xtream: xtreamFields
            case .m3uURL: linkFields
            #if !os(tvOS)
                case .m3uFile: fileFields
            #endif
            }

            Section {
                Toggle("Live TV only", isOn: $liveOnly)
            } footer: {
                Text("""
                Skips the movies and series: they are not downloaded or stored, and the Movies and \
                Series tabs are hidden unless another source has them.
                """)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add playlist")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add", action: add).disabled(!isValid)
                    }
                }
            }
            .disabled(isAdding)
        #if !os(tvOS)
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.data, .plainText]) { result in
                if case let .success(url) = result {
                    pickedFile = url
                }
            }
        #endif
    }

    // MARK: - Fields

    private var xtreamFields: some View {
        Section {
            TextField("Server address", text: $server, prompt: Text("http://provider.example:8080"))
                .textContentType(.URL)
                .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif
            TextField("Username", text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
            SecureField("Password", text: $password)
                .textContentType(.password)
        } footer: {
            Text("Your login is checked with the provider, then kept in the Keychain on this device.")
        }
    }

    private var linkFields: some View {
        Section {
            TextField("Playlist address", text: $link, prompt: Text("https://provider.example/playlist.m3u"))
                .textContentType(.URL)
                .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif
            TextField("TV guide address (optional)", text: $guideLink)
                .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif
        } footer: {
            Text("""
            The address is kept in the Keychain, because it often contains your login. \
            If the playlist names its own TV guide, you do not need to fill this in.
            """)
        }
    }

    #if !os(tvOS)
        private var fileFields: some View {
            Section {
                Button(pickedFile?.lastPathComponent ?? "Choose a file…") { showingFilePicker = true }
            } footer: {
                Text("Panop keeps its own copy. To update it, add the file again.")
            }
        }
    #endif

    // MARK: - Actions

    private var isValid: Bool {
        switch mode {
        case .xtream: !server.isBlank && !username.isBlank && !password.isEmpty
        case .m3uURL: !link.isBlank
        #if !os(tvOS)
            case .m3uFile: pickedFile != nil
        #endif
        }
    }

    private func add() {
        guard let draft = draft() else { return }
        errorMessage = nil
        isAdding = true
        Task {
            do {
                try await library.add(draft, includeVOD: !liveOnly)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isAdding = false
            }
        }
    }

    private func draft() -> PlaylistDraft? {
        switch mode {
        case .xtream:
            return .xtream(name: name, baseURL: server, username: username, password: password)
        case .m3uURL:
            return .m3uURL(name: name, url: link, guideURL: guideLink)
        #if !os(tvOS)
            case .m3uFile:
                return pickedFile.map { .m3uFile(name: name, fileURL: $0) }
        #endif
        }
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
