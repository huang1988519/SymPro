//
//  LLMOpenAPIConfig.swift
//  SymPro
//
//  Import/export JSON for OpenAI-compatible HTTP APIs (e.g. OpenAI, DashScope Qwen, DeepSeek).
//

import Foundation

/// Values persisted in UserDefaults + Keychain (API key) for future LLM features.
struct LLMOpenAPIConfig: Codable, Equatable {
    var baseURL: String
    var model: String
    /// When encoding for export, omit secret by default.
    var apiKey: String?
    /// HTTP header name for the API key (e.g. `Authorization`, `x-api-key`).
    var apiKeyHeader: String?
    /// User-visible name (maps to JSON key `description`).
    var providerDescription: String?
    /// `"internet"` or `"local"`.
    var hosting: String?
    /// Local gateway port (when `hosting` is local), e.g. Ollama default `11434`.
    var port: String?

    enum CodingKeys: String, CodingKey {
        case baseURL
        case model
        case apiKey
        case apiKeyHeader
        case hosting
        case providerDescription = "description"
        case port
    }
}

enum LLMOpenAPIJSONImport {
    /// Parses flexible JSON from tools / env files:
    /// - `baseURL` / `base_url` / `OPENAI_BASE_URL` / `openai_base_url`
    /// - `model` / `deployment` / `model_name`
    /// - `apiKey` / `api_key` / `OPENAI_API_KEY`
    static func parse(data: Data) throws -> LLMOpenAPIConfig {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        func str(_ keys: [String]) -> String? {
            for k in keys {
                if let v = obj[k] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return v.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }
        let base = str(["baseURL", "base_url", "OPENAI_BASE_URL", "openai_base_url"])
            ?? "https://api.openai.com/v1"
        let model = str(["model", "deployment", "model_name"]) ?? "gpt-4o-mini"
        let key = str(["apiKey", "api_key", "OPENAI_API_KEY"])
        let header = str(["apiKeyHeader", "api_key_header", "API_KEY_HEADER"])
        let desc = str(["description", "providerDescription", "name"])
        let hostMode = str(["hosting", "hostingMode"])
        let port = str(["port", "localPort"])
        return LLMOpenAPIConfig(
            baseURL: base,
            model: model,
            apiKey: key,
            apiKeyHeader: header,
            providerDescription: desc,
            hosting: hostMode,
            port: port
        )
    }

    static func encodeForExport(_ config: LLMOpenAPIConfig, includeAPIKey: Bool) throws -> Data {
        var c = config
        if !includeAPIKey { c.apiKey = nil }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(c)
    }
}
