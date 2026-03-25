//
//  LLMProviderSettingsSheet.swift
//  SymPro
//
//  Xcode-style grouped form: header, labeled rows, footer (Help / Delete / Cancel / Save).
//

import SwiftUI

struct LLMProviderSettingsSheet: View {
    @ObservedObject var settings: SettingsStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var apiKeyDraft: String = ""
    @State private var apiKeySaveError: String?
    @State private var showAPIKeyPlainText: Bool = false
    @State private var availableModels: [String] = []
    @State private var isFetchingModels: Bool = false
    @State private var modelsFetchError: String?
    @State private var showHelp: Bool = false
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    headerRow
                }
                
                Section {
                    LabeledContent(L10n.t("URL")) {
                        TextField("", text: $settings.llmBaseURL, prompt: Text("https://api.host.com/v1"))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section {
                    LabeledContent(L10n.t("API Key")) {
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 8) {
                                if showAPIKeyPlainText {
                                    TextField("", text: $apiKeyDraft)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("", text: $apiKeyDraft)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.roundedBorder)
                                }
                                Button {
                                    showAPIKeyPlainText.toggle()
                                } label: {
                                    Image(systemName: showAPIKeyPlainText ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.plain)
                            }
//                            Text(settings.llmAPIKeyConfigured ? L10n.t("Saved in Keychain") : L10n.t("Not saved"))
//                                .font(.caption)
//                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent(L10n.t("API Key Header")) {
                        TextField("", text: $settings.llmAPIKeyHeaderName, prompt: Text("Authorization"))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text(L10n.t("Authentication"))
                }
                
                Section {
//                        LabeledContent(L10n.t("URL")) {
//                            TextField("", text: $settings.llmBaseURL, prompt: Text("https://api.host.com/v1"))
//                                .textFieldStyle(.plain)
//                                .multilineTextAlignment(.trailing)
//                        }
                        LabeledContent(L10n.t("Model")) {
                            HStack(spacing: 8) {
                                TextField("", text: $settings.llmModel, prompt: Text("gpt-4o-mini"))
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    Task { await fetchAvailableModels() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .help(L10n.t("Fetch Models"))
                                .disabled(isFetchingModels)
                                if isFetchingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        if !availableModels.isEmpty {
                            LabeledContent(L10n.t("Available models")) {
                                Picker("", selection: $settings.llmModel) {
                                    ForEach(availableModels, id: \.self) { modelID in
                                        Text(modelID).tag(modelID)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 280, alignment: .trailing)
                            }
                        }
                        if let modelsFetchError, !modelsFetchError.isEmpty {
                            Text(modelsFetchError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                Section {
                    LabeledContent(L10n.t("Description")) {
                        TextField("", text: $settings.llmProviderDisplayName, prompt: Text(L10n.t("My Account")))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            if let err = apiKeySaveError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            footerBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 440, idealWidth: 480)
        .frame(minHeight: 520)
        .id(themeRefreshID)
        .alert(L10n.t("Provider help"), isPresented: $showHelp) {
            Button(L10n.t("Done")) { }
        } message: {
            Text(L10n.t("Provider help message"))
        }
        .confirmationDialog(L10n.t("Delete Provider"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(L10n.t("Delete Provider"), role: .destructive) {
                settings.resetLLMProviderConfiguration()
                apiKeyDraft = ""
                showAPIKeyPlainText = false
                availableModels = []
                modelsFetchError = nil
                dismiss()
            }
            Button(L10n.t("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("Delete provider confirmation"))
        }
        .onAppear {
            // Local hosting has been removed from settings UI.
            if settings.llmHostingMode == .local {
                settings.llmHostingMode = .internet
            }
            loadSavedAPIKeyDraft()
        }
    }

    private var themeRefreshID: String {
        "\(settings.appearanceMode.rawValue)-\(colorScheme == .dark ? "dark" : "light")-sheet"
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "globe")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(providerHeaderTitle)
                    .font(.title3.weight(.semibold))
                Text(hostingSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var providerHeaderTitle: String {
        let d = settings.llmProviderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { return d }
        let u = settings.llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: u), let host = url.host, !host.isEmpty { return host }
        if !u.isEmpty { return u }
        return L10n.t("Model Provider")
    }

    private var hostingSubtitle: String {
        L10n.t("Internet hosted model provider")
    }

    private var footerBar: some View {
        HStack(alignment: .center) {
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Provider help"))

            Button(L10n.t("Delete Provider")) {
                showDeleteConfirm = true
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.12), in: Capsule())

            Spacer()

            Button(L10n.t("Cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(L10n.t("Save")) {
                saveAndDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    private func saveAndDismiss() {
        let t = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            do {
                try settings.saveLLMAPIKey(t)
                apiKeyDraft = t
                apiKeySaveError = nil
            } catch {
                apiKeySaveError = error.localizedDescription
                return
            }
        }
        dismiss()
    }

    private func fetchAvailableModels() async {
        let base = settings.llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            modelsFetchError = L10n.t("Please enter URL first.")
            return
        }
        guard let endpoint = modelsEndpointURL(from: base) else {
            modelsFetchError = L10n.t("Invalid URL.")
            return
        }

        isFetchingModels = true
        modelsFetchError = nil
        defer { isFetchingModels = false }

        do {
            let key = {
                let draft = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !draft.isEmpty { return draft }
                return settings.llmAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }()
            let configuredHeader = settings.llmResolvedAPIKeyHeaderName()
            let firstTry = try await performModelsRequest(
                endpoint: endpoint,
                apiKey: key,
                headerName: configuredHeader
            )

            var finalData = firstTry.data
            var finalHTTP = firstTry.http
            // Some OpenAI-compatible gateways only accept Authorization: Bearer <key>.
            if finalHTTP.statusCode == 401, !key.isEmpty, configuredHeader.caseInsensitiveCompare("Authorization") != .orderedSame {
                let retry = try await performModelsRequest(
                    endpoint: endpoint,
                    apiKey: key,
                    headerName: "Authorization"
                )
                finalData = retry.data
                finalHTTP = retry.http
            }

            guard (200 ... 299).contains(finalHTTP.statusCode) else {
                let body = String(data: finalData, encoding: .utf8) ?? ""
                if body.isEmpty {
                    modelsFetchError = L10n.tFormat("Request failed (%d).", finalHTTP.statusCode)
                } else {
                    modelsFetchError = body
                }
                if finalHTTP.statusCode == 401 {
                    modelsFetchError = (modelsFetchError ?? "") + " " + L10n.t("Check API Key/Header.")
                }
                return
            }

            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: finalData)
            let ids = Array(Set(decoded.data.map(\.id))).sorted()
            availableModels = ids
            // 每次成功拉取后，主动切换到列表第一个模型，保持交互一致。
            if let first = ids.first {
                settings.llmModel = first
            }
            if ids.isEmpty {
                modelsFetchError = L10n.t("No models returned from endpoint.")
            }
        } catch {
            modelsFetchError = error.localizedDescription
        }
    }

    private func modelsEndpointURL(from baseURLString: String) -> URL? {
        guard var comps = URLComponents(string: baseURLString) else { return nil }
        let path = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            comps.path = "/models"
        } else if path.hasSuffix("models") {
            comps.path = "/" + path
        } else {
            comps.path = "/" + path + "/models"
        }
        comps.query = nil
        comps.fragment = nil
        return comps.url
    }

    private func performModelsRequest(endpoint: URL, apiKey: String, headerName: String) async throws -> (data: Data, http: HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        if !apiKey.isEmpty {
            if headerName.caseInsensitiveCompare("Authorization") == .orderedSame {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: headerName)
            } else {
                request.setValue(apiKey, forHTTPHeaderField: headerName)
            }
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private func loadSavedAPIKeyDraft() {
        if let saved = settings.llmAPIKey(), !saved.isEmpty {
            apiKeyDraft = saved
        } else {
            apiKeyDraft = ""
        }
    }
}

private struct OpenAIModelsResponse: Decodable {
    let data: [OpenAIModelItem]
}

private struct OpenAIModelItem: Decodable {
    let id: String
}
