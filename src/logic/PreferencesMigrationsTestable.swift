import Foundation

/// Version predicates behind PreferencesMigrations' legacy migration chain, extracted so they can be
/// unit-tested without touching UserDefaults.
class PreferencesMigrationsTestable {
    /// AltTab shipped 1.x through 10.12.0; this fork restarted numbering at 0.x. A 0.x plist was therefore
    /// written by the fork, which has never held the AltTab-era preference schema, so none of the legacy
    /// migrations apply to it.
    ///
    /// Comparing against App.version instead (as this used to) does not work across the fork boundary: every
    /// AltTab version is numerically *above* 0.x, so genuinely old AltTab prefs looked like a downgrade and
    /// were skipped, while the fork's own prefs matched every threshold and re-ran the whole chain.
    static func isAltTabEraVersion(_ version: String) -> Bool {
        version.compare("1.0.0", options: .numeric) != .orderedAscending
    }

    /// whether the migration guarded by `versionThreshold` still needs to be applied to a plist last written
    /// by AltTab version `versionInPlist`
    static func shouldRun(_ versionInPlist: String, _ versionThreshold: String) -> Bool {
        // x.compare(y) is .orderedDescending if x > y
        versionInPlist.compare(versionThreshold, options: .numeric) != .orderedDescending
    }
}
