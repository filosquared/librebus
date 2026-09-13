import SwiftUI

struct ContentView: View {
    @AppStorage("librebusServerURL") private var savedServerURL = ""
    @State private var connectedURL: URL?
    @State private var showingServerSetup = false

    var body: some View {
        NavigationStack {
            Group {
                if let connectedURL {
                    LibrebusWebView(url: connectedURL)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ServerSetupView(serverURL: $savedServerURL) { url in
                        connectedURL = url
                    }
                }
            }
            .navigationTitle("Librebus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if connectedURL != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Server") {
                            showingServerSetup = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingServerSetup) {
            NavigationStack {
                ServerSetupView(serverURL: $savedServerURL) { url in
                    connectedURL = url
                    showingServerSetup = false
                }
                .navigationTitle("Server")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            connectedURL = validatedURL(from: savedServerURL)
        }
    }

    private func validatedURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}

private struct ServerSetupView: View {
    @Binding var serverURL: String
    let onConnect: (URL) -> Void
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Connect to Librebus")
                .font(.title2.weight(.semibold))

            Text("Enter the address of your Librebus server. For a production deployment, use an HTTPS address.")
                .foregroundStyle(.secondary)

            TextField("https://librebus.example.com", text: $serverURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.go)
                .onSubmit(connect)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(action: connect) {
                Text("Connect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(24)
    }

    private func connect() {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            errorMessage = "Enter a valid http:// or https:// server address."
            return
        }

        serverURL = url.absoluteString
        errorMessage = nil
        onConnect(url)
    }
}
