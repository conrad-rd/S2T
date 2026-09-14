import Foundation
import Darwin

@MainActor final class FnSystemAction {
    private let domain = "com.apple.HIToolbox" as CFString
    private let key = "AppleFnUsageType" as CFString
    private let defaults: UserDefaults
    private let readValue: (() -> Int?)?
    private let writeValue: ((Int?) -> Bool)?
    private let notifyChange: () -> Void
    private var active = false

    init(defaults: UserDefaults = .standard, read: (() -> Int?)? = nil,
         write: ((Int?) -> Bool)? = nil, notify: (() -> Void)? = nil) {
        self.defaults = defaults
        readValue = read
        writeValue = write
        notifyChange = notify ?? {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("AppleKeyboardPreferencesFnKeySettingChangedNotification"),
                object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    func begin() -> Bool {
        // Rechecks must not overwrite a change made in Keyboard settings.
        if active { return current() == 0 && effective() == 0 }
        if !defaults.bool(forKey: "fnOverrideHasBackup") {
            let previous = current()
            defaults.set(previous != nil, forKey: "fnOverrideHadValue")
            defaults.set(previous ?? 0, forKey: "fnOverridePreviousValue")
            defaults.set(effective(), forKey: "fnOverridePreviousEffectiveValue")
            defaults.set(true, forKey: "fnOverrideHasBackup")
            defaults.synchronize()
        }
        guard write(0), current() == 0 else { return false }
        active = true
        return true
    }

    func retry() -> Bool { active = false; return begin() }

    func restore() {
        guard active || defaults.bool(forKey: "fnOverrideHasBackup") else { return }
        if current() == 0 {
            let previous = defaults.bool(forKey: "fnOverrideHadValue") ? defaults.integer(forKey: "fnOverridePreviousValue") : nil
            guard write(previous), current() == previous else { return }
        }
        defaults.set(false, forKey: "fnOverrideHasBackup")
        defaults.synchronize()
        active = false
    }

    private func current() -> Int? {
        if let readValue { return readValue() }
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber)?.intValue
    }

    private func effective() -> Int? {
        if let readValue { return readValue() }
        return NativeFnPreferences.get.map { Int($0()) } ?? current()
    }

    private func write(_ value: Int?) -> Bool {
        let saved: Bool
        if let writeValue { saved = writeValue(value) }
        else {
            let appliedValue = value ?? defaults.object(forKey: "fnOverridePreviousEffectiveValue") as? Int ?? 0
            if let update = NativeFnPreferences.update {
                update(Int32(appliedValue))
            } else if effective() != appliedValue {
                return false
            }
            CFPreferencesSetValue(key, value.map(NSNumber.init(value:)), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            saved = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                && effective() == appliedValue
        }
        if saved { notifyChange() }
        return saved
    }
}

// KeyboardSettings.appex uses this Int32 getter/setter pair. Resolve at runtime
// because these HIToolbox functions are private and may be absent on future macOS.
enum NativeFnPreferences {
    private static let library = dlopen("/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/HIToolbox", RTLD_LAZY | RTLD_LOCAL)
    static let get: (@convention(c) () -> Int32)? = {
        guard let library, let symbol = dlsym(library, "TISGetFnUsageType") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
    }()
    static let update: (@convention(c) (Int32) -> Void)? = {
        guard let library, let symbol = dlsym(library, "TISUpdateFnUsageType") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (Int32) -> Void).self)
    }()
}
