#if os(tvOS)
    import SwiftUI

    /// Adding a WireGuard configuration on Apple TV, which has no multi-line text entry: one field for each
    /// setting. Each field's keyboard can be an iPhone's, and a value pasted there arrives whole, which is how a
    /// 44-character key is entered. (On an iPhone, iPad or Mac the whole file is pasted instead.)
    struct WireGuardFieldsForm: View {
        let tunnel: TunnelController
        @Environment(\.dismiss) private var dismiss
        @State private var privateKey = ""
        @State private var address = ""
        @State private var dns = ""
        @State private var publicKey = ""
        @State private var endpoint = ""
        @State private var presharedKey = ""
        @State private var problem: String?

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        SecureField("Private key", text: $privateKey)
                        TextField("Address, for example 10.2.0.2/32", text: $address)
                        TextField("DNS, for example 10.2.0.1", text: $dns)
                    } header: {
                        Text("Your device")
                    }
                    Section {
                        TextField("Public key", text: $publicKey)
                        TextField("Server, for example 185.159.157.10:51820", text: $endpoint)
                        SecureField("Preshared key (if your provider gives one)", text: $presharedKey)
                    } header: {
                        Text("The VPN server")
                    } footer: {
                        VStack(alignment: .leading, spacing: 8) {
                            if let problem {
                                Text(problem).foregroundStyle(.orange)
                            }
                            Text("""
                            Copy these from your provider's WireGuard file. In each field, choose your iPhone as the \
                            keyboard and paste.
                            """)
                        }
                    }
                    Section {
                        Button("Add") { add() }
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
                .navigationTitle("WireGuard configuration")
            }
        }

        private func add() {
            var lines = [
                "[Interface]", "PrivateKey = \(clean(privateKey))", "Address = \(clean(address))",
                "DNS = \(clean(dns))",
                "", "[Peer]", "PublicKey = \(clean(publicKey))"
            ]
            if !clean(presharedKey).isEmpty {
                lines.append("PresharedKey = \(clean(presharedKey))")
            }
            lines += ["AllowedIPs = 0.0.0.0/0, ::/0", "Endpoint = \(clean(endpoint))", "PersistentKeepalive = 25"]
            do {
                try tunnel.importConfiguration(lines.joined(separator: "\n"))
                privateKey = ""
                presharedKey = ""
                dismiss()
            } catch {
                problem = "\(error)"
            }
        }

        private func clean(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
#endif
