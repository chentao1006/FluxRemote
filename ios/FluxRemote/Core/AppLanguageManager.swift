import Foundation
import Observation
import SwiftUI

// MARK: - Language Management

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case chinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case german = "de"
    case french = "fr"
    case italian = "it"
    
    var id: String { self.rawValue }
    
    var locale: Locale? {
        switch self {
        case .system: return nil
        case .chinese: return Locale(identifier: "zh-Hans")
        case .traditionalChinese: return Locale(identifier: "zh-Hant")
        case .english: return Locale(identifier: "en")
        case .japanese: return Locale(identifier: "ja")
        case .korean: return Locale(identifier: "ko")
        case .spanish: return Locale(identifier: "es")
        case .german: return Locale(identifier: "de")
        case .french: return Locale(identifier: "fr")
        case .italian: return Locale(identifier: "it")
        }
    }
    
    var displayNameKey: String {
        switch self {
        case .system: return "common.systemDefault"
        case .chinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .italian: return "Italiano"
        }
    }
}

@MainActor
@Observable
class AppLanguageManager {
    var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "app_language")
        }
    }
    
    init() {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? "system"
        self.selectedLanguage = AppLanguage(rawValue: saved) ?? .system
    }
    
    func t(_ key: String) -> String {
        let langCode = selectedLanguage == .system ? nil : selectedLanguage.rawValue
        
        // 1. Try to find the bundle for the selected language
        if let langCode = langCode,
           let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let result = bundle.localizedString(forKey: key, value: nil, table: nil)
            if result != key {
                return result
            }
        }
        
        // 2. Fallback to NSLocalizedString which handles system language correctly
        // and also looks into the main bundle for .xcstrings entries.
        return NSLocalizedString(key, value: key, comment: "")
    }

    func systemT(_ key: String) -> String {
        NSLocalizedString(key, value: key, comment: "")
    }

    var aiResponseLanguage: String {
        let langCode = selectedLanguage == .system ? Locale.current.language.languageCode?.identifier : selectedLanguage.rawValue
        if langCode?.hasPrefix("zh") == true {
            return "Chinese"
        }
        if langCode?.hasPrefix("ja") == true {
            return "Japanese"
        }
        if langCode?.hasPrefix("ko") == true {
            return "Korean"
        }
        if langCode?.hasPrefix("es") == true {
            return "Spanish"
        }
        if langCode?.hasPrefix("de") == true {
            return "German"
        }
        if langCode?.hasPrefix("fr") == true {
            return "French"
        }
        if langCode?.hasPrefix("it") == true {
            return "Italian"
        }
        return "English"
    }
}
