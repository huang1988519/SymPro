import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

enum RegionPolicy {
    static var isChinaMainland: Bool {
        // Prefer App Store storefront (distribution context), fallback to device locale.
        if isChinaMainlandStorefront { return true }
        if let id = Locale.current.region?.identifier {
            return id.uppercased() == "CN"
        }
        let legacy = (Locale.current as NSLocale).object(forKey: .countryCode) as? String
        return legacy?.uppercased() == "CN"
    }

    static var isChinaMainlandStorefront: Bool {
        #if canImport(StoreKit)
        // StoreKit storefront uses ISO 3166-1 alpha-3 in many cases (e.g. "CHN").
        let cc = SKPaymentQueue.default().storefront?.countryCode.uppercased()
        return cc == "CHN" || cc == "CN"
        #else
        return false
        #endif
    }
}

