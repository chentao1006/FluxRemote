import Foundation
import Observation
import SwiftUI

// MARK: - Language Management

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case chinese = "zh-Hans"
    case english = "en"
    
    var id: String { self.rawValue }
    
    var locale: Locale? {
        switch self {
        case .system: return nil
        case .chinese: return Locale(identifier: "zh-Hans")
        case .english: return Locale(identifier: "en")
        }
    }
    
    var displayNameKey: String {
        switch self {
        case .system: return "common.systemDefault"
        case .chinese: return "简体中文"
        case .english: return "English"
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
}
