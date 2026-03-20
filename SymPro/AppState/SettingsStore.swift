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
    private let defaultFontSize: CGFloat = 12

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

    override init() {
        let v = UserDefaults.standard.double(forKey: fontSizeKey)
        resultFontSize = v > 0 ? v : defaultFontSize
        let raw = UserDefaults.standard.string(forKey: appearanceModeKey) ?? AppearanceMode.system.rawValue
        appearanceMode = AppearanceMode(rawValue: raw) ?? .system
        super.init()
    }
}
