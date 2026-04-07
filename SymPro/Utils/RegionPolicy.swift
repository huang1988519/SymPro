import Foundation

enum RegionPolicy {
    static var isChinaMainland: Bool {
        if let id = Locale.current.region?.identifier {
            return id.uppercased() == "CN"
        }
        let legacy = (Locale.current as NSLocale).object(forKey: .countryCode) as? String
        return legacy?.uppercased() == "CN"
    }
}

