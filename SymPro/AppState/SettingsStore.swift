//
//  SettingsStore.swift
//  SymPro
//

import Foundation
import SwiftUI
import Combine

final class SettingsStore: NSObject, ObservableObject {
    static let shared = SettingsStore()

    private let fontSizeKey = "sympro.resultFontSize"
    private let appearanceModeKey = "sympro.appearanceMode"
    private let llmBaseURLKey = "sympro.llm.baseURL"
    private let llmModelKey = "sympro.llm.model"
    private let llmPresetKey = "sympro.llm.providerPreset"
    private let llmHostingModeKey = "sympro.llm.hostingMode"
    private let llmProviderDisplayNameKey = "sympro.llm.providerDisplayName"
    private let llmAPIKeyHeaderKey = "sympro.llm.apiKeyHeader"
    private let llmLocalPortKey = "sympro.llm.localPort"
    private let keychainService = "com.hwh.SymPro"
    private let llmAPIKeyAccount = "llm.openai_compatible.api_key"
    private let defaultFontSize: CGFloat = 12

    /// OpenAI-compatible Chat Completions provider presets (base URL + default model).
    enum LLMProviderPreset: String, CaseIterable, Identifiable {
        case custom
        case openai
        case gemini
        case dashscope
        case deepseek
        case mistral
        case groq
        case moonshot
        case openrouter
        case zhipu

        var id: String { rawValue }

        var defaultBaseURL: String {
            switch self {
            case .custom: return ""
            case .openai: return "https://api.openai.com/v1"
            case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
            case .dashscope: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
            case .deepseek: return "https://api.deepseek.com/v1"
            case .mistral: return "https://api.mistral.ai/v1"
            case .groq: return "https://api.groq.com/openai/v1"
            case .moonshot: return "https://api.moonshot.cn/v1"
            case .openrouter: return "https://openrouter.ai/api/v1"
            case .zhipu: return "https://open.bigmodel.cn/api/paas/v4"
            }
        }

        var defaultModel: String {
            switch self {
            case .custom: return ""
            case .openai: return "gpt-4o-mini"
            case .gemini: return "gemini-2.0-flash"
            case .dashscope: return "qwen-turbo"
            case .deepseek: return "deepseek-chat"
            case .mistral: return "mistral-small-latest"
            case .groq: return "llama-3.3-70b-versatile"
            case .moonshot: return "moonshot-v1-8k"
            case .openrouter: return "openai/gpt-4o-mini"
            case .zhipu: return "glm-4-flash"
            }
        }
    }

    /// Internet vs local (e.g. Ollama) — mirrors Xcode Intelligence “Hosted” segments.
    enum LLMHostingMode: String, CaseIterable, Identifiable, Codable {
        case internet
        case local

        var id: String { rawValue }
    }

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        var preferredColorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    @Published var resultFontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(resultFontSize, forKey: fontSizeKey)
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceModeKey)
        }
    }

    /// Base URL for OpenAI-compatible APIs (usually ends with `/v1`).
    @Published var llmBaseURL: String {
        didSet {
            UserDefaults.standard.set(llmBaseURL, forKey: llmBaseURLKey)
        }
    }

    /// Model name for Chat Completions (e.g. `gpt-4o-mini`, `qwen-turbo`).
    @Published var llmModel: String {
        didSet {
            UserDefaults.standard.set(llmModel, forKey: llmModelKey)
        }
    }

    @Published var llmProviderPreset: LLMProviderPreset {
        didSet {
            UserDefaults.standard.set(llmProviderPreset.rawValue, forKey: llmPresetKey)
        }
    }

    @Published var llmHostingMode: LLMHostingMode {
        didSet {
            UserDefaults.standard.set(llmHostingMode.rawValue, forKey: llmHostingModeKey)
            if llmHostingMode == .local {
                // 切换到本地托管时，不沿用互联网服务商的模型值，避免误调用远端模型 ID。
                if oldValue != .local {
                    llmModel = ""
                }
                if llmLocalPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    llmLocalPort = Self.parsePortFrom127BaseURL(llmBaseURL) ?? "11434"
                }
                let port = Self.normalizedPortString(llmLocalPort)
                llmBaseURL = "http://127.0.0.1:\(port)/v1"
            }
        }
    }

    /// User label for the single provider row (e.g. “My Account”).
    @Published var llmProviderDisplayName: String {
        didSet {
            UserDefaults.standard.set(llmProviderDisplayName, forKey: llmProviderDisplayNameKey)
        }
    }

    /// Local OpenAI-compatible gateway port only (e.g. Ollama). Base URL becomes `http://127.0.0.1:{port}/v1`.
    @Published var llmLocalPort: String {
        didSet {
            UserDefaults.standard.set(llmLocalPort, forKey: llmLocalPortKey)
            if llmHostingMode == .local {
                let port = Self.normalizedPortString(llmLocalPort)
                let newURL = "http://127.0.0.1:\(port)/v1"
                if llmBaseURL != newURL {
                    llmBaseURL = newURL
                }
            }
        }
    }

    /// Header field for the API key (e.g. `Authorization`, `x-api-key`).
    @Published var llmAPIKeyHeaderName: String {
        didSet {
            UserDefaults.standard.set(llmAPIKeyHeaderName, forKey: llmAPIKeyHeaderKey)
        }
    }

    /// Whether a non-empty API key exists in Keychain (never exposes the secret).
    @Published private(set) var llmAPIKeyConfigured: Bool = false

    override init() {
        let v = UserDefaults.standard.double(forKey: fontSizeKey)
        resultFontSize = v > 0 ? v : defaultFontSize
        let raw = UserDefaults.standard.string(forKey: appearanceModeKey) ?? AppearanceMode.system.rawValue
        appearanceMode = AppearanceMode(rawValue: raw) ?? .system
        llmBaseURL = UserDefaults.standard.string(forKey: llmBaseURLKey) ?? ""
        llmModel = UserDefaults.standard.string(forKey: llmModelKey) ?? ""
        let presetRaw = UserDefaults.standard.string(forKey: llmPresetKey) ?? LLMProviderPreset.custom.rawValue
        llmProviderPreset = LLMProviderPreset(rawValue: presetRaw) ?? .custom
        let hostingRaw = UserDefaults.standard.string(forKey: llmHostingModeKey) ?? LLMHostingMode.internet.rawValue
        llmHostingMode = LLMHostingMode(rawValue: hostingRaw) ?? .internet
        llmProviderDisplayName = UserDefaults.standard.string(forKey: llmProviderDisplayNameKey) ?? ""
        llmAPIKeyHeaderName = UserDefaults.standard.string(forKey: llmAPIKeyHeaderKey) ?? "Authorization"
        llmLocalPort = UserDefaults.standard.string(forKey: llmLocalPortKey) ?? ""
        super.init()
        if llmHostingMode == .local {
            if llmLocalPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                llmLocalPort = Self.parsePortFrom127BaseURL(llmBaseURL) ?? "11434"
            }
            let port = Self.normalizedPortString(llmLocalPort)
            llmBaseURL = "http://127.0.0.1:\(port)/v1"
        }
        refreshLLMAPIKeyConfiguredFlag()
    }

    private static func normalizedPortString(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "11434" }
        let digits = t.filter(\.isNumber)
        guard let n = Int(digits), (1 ... 65_535).contains(n) else { return "11434" }
        return String(n)
    }

    /// Parses port from a localhost base URL (OpenAI-compatible), or nil if not local.
    static func parsePortFrom127BaseURL(_ baseURL: String) -> String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let host = url.host else { return nil }
        guard host == "127.0.0.1" || host == "localhost" || host == "::1" else { return nil }
        if let p = url.port { return String(p) }
        return "11434"
    }

    /// Normalized header name for HTTP clients (default OpenAI-style `Authorization`).
    func llmResolvedAPIKeyHeaderName() -> String {
        let t = llmAPIKeyHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Authorization" : t
    }

    /// Resolved OpenAI-compatible base URL for local hosting (for UI / debugging).
    func llmLocalGatewayURLDisplay() -> String {
        let port = Self.normalizedPortString(llmLocalPort)
        return "http://127.0.0.1:\(port)/v1"
    }

    /// Applies preset URL + model, or clears them when switching to **Custom** (user fills manually).
    func applyLLMPresetDefaults() {
        if llmProviderPreset == .custom {
            llmBaseURL = ""
            llmModel = ""
            return
        }
        llmBaseURL = llmProviderPreset.defaultBaseURL
        llmModel = llmProviderPreset.defaultModel
    }

    func refreshLLMAPIKeyConfiguredFlag() {
        let has = (KeychainHelper.getString(service: keychainService, account: llmAPIKeyAccount) ?? "").isEmpty == false
        if llmAPIKeyConfigured != has {
            llmAPIKeyConfigured = has
        }
    }

    /// For future network calls: returns the stored API key, or nil.
    func llmAPIKey() -> String? {
        let s = KeychainHelper.getString(service: keychainService, account: llmAPIKeyAccount)
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    func saveLLMAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try KeychainHelper.setString(trimmed, service: keychainService, account: llmAPIKeyAccount)
        refreshLLMAPIKeyConfiguredFlag()
    }

    func clearLLMAPIKey() {
        KeychainHelper.delete(service: keychainService, account: llmAPIKeyAccount)
        refreshLLMAPIKeyConfiguredFlag()
    }

    /// Clears URL, model, description, API key, and resets to Internet + Custom (like deleting the provider in Xcode).
    func resetLLMProviderConfiguration() {
        clearLLMAPIKey()
        llmProviderPreset = .custom
        llmAPIKeyHeaderName = "Authorization"
        llmProviderDisplayName = ""
        llmModel = ""
        llmLocalPort = "11434"
        llmHostingMode = .internet
        llmBaseURL = ""
    }

    func currentLLMOpenAPIConfig() -> LLMOpenAPIConfig {
        let desc = llmProviderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let portOut: String? = llmHostingMode == .local
            ? Self.normalizedPortString(llmLocalPort)
            : nil
        return LLMOpenAPIConfig(
            baseURL: llmBaseURL,
            model: llmModel,
            apiKey: llmAPIKey(),
            apiKeyHeader: llmHostingMode == .internet ? llmResolvedAPIKeyHeaderName() : nil,
            providerDescription: desc.isEmpty ? nil : desc,
            hosting: llmHostingMode.rawValue,
            port: portOut
        )
    }

    func applyImportedLLMConfig(_ config: LLMOpenAPIConfig) throws {
        let incomingHost = config.hosting?.lowercased()
        let portStr = config.port?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasExplicitPort = !portStr.isEmpty
        let fromURL = Self.parsePortFrom127BaseURL(config.baseURL)

        let useLocal: Bool = {
            if incomingHost == "local" || incomingHost == "localhost" { return true }
            if incomingHost == "internet" || incomingHost == "remote" { return false }
            if hasExplicitPort { return true }
            if fromURL != nil { return true }
            return false
        }()

        if useLocal {
            if hasExplicitPort {
                llmLocalPort = Self.normalizedPortString(portStr)
            } else if let fromURL {
                llmLocalPort = fromURL
            } else {
                llmLocalPort = "11434"
            }
            llmHostingMode = .local
        } else {
            llmHostingMode = .internet
            llmBaseURL = config.baseURL
        }

        llmModel = config.model
        if let key = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            try KeychainHelper.setString(key, service: keychainService, account: llmAPIKeyAccount)
        }
        if let h = config.apiKeyHeader?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            llmAPIKeyHeaderName = h
        }
        if let d = config.providerDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            llmProviderDisplayName = d
        }
        refreshLLMAPIKeyConfiguredFlag()
    }
}
