import SwiftUI

struct FluxLoginView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    
    @State private var panelURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var serverName: String = ""
    @FocusState private var focusedField: Field?
    var isAddingServer: Bool = false
    var initialURL: String? = nil
    var initialServerName: String? = nil
    @Environment(\.dismiss) private var dismiss
    
    enum Field {
        case url, username, password, serverName
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 32) {
                            // Header Section
                            VStack(spacing: 8) {
                                Text(languageManager.t("login.headerTitle"))
                                    .font(.title)
                                    .fontWeight(.bold)
                            }
                            .padding(.top, 60)
                            .padding(.bottom, 10)
                            
                            // Form Section
                            VStack(alignment: .leading, spacing: 24) {
                                // Server Info
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(languageManager.t("settings.server"))
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 8)
                                    
                                    VStack(spacing: 0) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "link")
                                                .foregroundStyle(Color.accentColor)
                                                .frame(width: 20)
                                            TextField(languageManager.t("login.serverURL"), text: $panelURL)
                                                .keyboardType(.URL)
                                                .autocorrectionDisabled()
                                                .textInputAutocapitalization(.never)
                                                .focused($focusedField, equals: .url)
                                                .submitLabel(.next)
                                        }
                                        .padding()
                                        
                                        if isAddingServer || !serverName.isEmpty {
                                            Divider()
                                                .padding(.leading, 48)
                                            
                                            HStack(spacing: 12) {
                                                Image(systemName: "tag")
                                                    .foregroundStyle(Color.accentColor)
                                                    .frame(width: 20)
                                                TextField(languageManager.t("settings.serverName"), text: $serverName)
                                                    .disabled(!isAddingServer)
                                                    .focused($focusedField, equals: .serverName)
                                                    .submitLabel(.next)
                                            }
                                            .padding()
                                        }
                                    }
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                
                                // Credentials
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(languageManager.t("settings.account"))
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 8)
                                    
                                    VStack(spacing: 0) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "person")
                                                .foregroundStyle(Color.accentColor)
                                                .frame(width: 20)
                                            TextField(languageManager.t("login.username"), text: $username)
                                                .autocorrectionDisabled()
                                                .textInputAutocapitalization(.never)
                                                .focused($focusedField, equals: .username)
                                                .submitLabel(.next)
                                        }
                                        .padding()
                                        
                                        Divider()
                                            .padding(.leading, 48)
                                        
                                        HStack(spacing: 12) {
                                            Image(systemName: "key")
                                                .foregroundStyle(Color.accentColor)
                                                .frame(width: 20)
                                            SecureField(languageManager.t("login.password"), text: $password)
                                                .focused($focusedField, equals: .password)
                                                .submitLabel(.go)
                                        }
                                        .padding()
                                    }
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .padding(.horizontal)
                            
                            if let error = apiClient.errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                    Text(error)
                                }
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            
                            Button(action: login) {
                                Group {
                                    if apiClient.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text(languageManager.t("login.loginBtn"))
                                            .fontWeight(.bold)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 44)
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .padding(.horizontal)
                            .padding(.top, 10)
                            .disabled(apiClient.isLoading || panelURL.isEmpty || username.isEmpty || password.isEmpty)
                        }
                        .frame(maxWidth: 400)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .onSubmit {
                switch focusedField {
                case .url: focusedField = isAddingServer ? .serverName : .username
                case .serverName: focusedField = .username
                case .username: focusedField = .password
                default: login()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                if isAddingServer {
                    panelURL = ""
                    serverName = ""
                    username = ""
                    password = ""
                } else if let initialURL {
                    panelURL = initialURL
                    if let initialServerName {
                        serverName = initialServerName
                    }
                } else if let savedURL = UserDefaults.standard.string(forKey: "flux_remote_url") {
                    panelURL = savedURL
                }
                
                // Set initial focus
                if panelURL.isEmpty {
                    focusedField = .url
                } else if username.isEmpty {
                    focusedField = .username
                }
            }
        }
    }
    func login() {
        // Auto-fix URL if missing protocol
        var finalURL = panelURL
        if !finalURL.lowercased().hasPrefix("http://") && !finalURL.lowercased().hasPrefix("https://") {
            finalURL = "https://" + finalURL
        }
        
        // Fix server name if empty
        if isAddingServer && serverName.isEmpty {
            serverName = panelURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            if serverName.hasSuffix("/") { serverName.removeLast() }
        }
        
        Task {
            // If adding a server, check if it already exists or add to ServerManager first
            if isAddingServer {
                var cleanPanelURL = finalURL
                if cleanPanelURL.hasSuffix("/") { cleanPanelURL.removeLast() }
                
                if !ServerManager.shared.servers.contains(where: { $0.url == cleanPanelURL }) {
                    let newServer = ServerConfig(name: serverName, url: cleanPanelURL)
                    ServerManager.shared.addServer(newServer)
                }
            }
            
            await apiClient.login(urlString: finalURL, credentials: [
                "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": password
            ])
            
            if apiClient.isAuthenticated {
                if isAddingServer {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    FluxLoginView()
        .environment(RemoteAPIClient())
        .environment(AppLanguageManager())
}
