import Foundation
import Darwin
import S2TCore

enum CreditDeviceIdentity {
    static func current() -> CreditDevice {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: "credits.deviceID").flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(id.uuidString, forKey: "credits.deviceID")
        var size = 0
        var model = ""
        if sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size < 256 {
            var bytes = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 { model = String(cString: bytes) }
        }
        let families = [("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"), ("Macmini", "Mac mini"), ("MacPro", "Mac Pro"), ("iMac", "iMac")]
        return CreditDevice(id: id, name: families.first { model.hasPrefix($0.0) }?.1 ?? "Mac")
    }
}
