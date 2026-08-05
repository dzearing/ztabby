import XCTest

final class PreferencesMigrationsTests: XCTestCase {
    // every threshold in PreferencesMigrations.updateToNewPreferences
    private static let legacyThresholds = [
        "10.2.0", "9.0.0", "7.27.0", "7.26.0", "7.25.0", "7.13.1", "7.8.0",
        "7.0.0", "6.43.0", "6.28.1", "6.27.1", "6.23.0", "6.18.1",
    ]

    func testForkVersionsAreNotAltTabEra() throws {
        for version in ["0.1.0", "0.3.2", "0.4.0", "0.10.0", "0.99.3"] {
            XCTAssertFalse(PreferencesMigrationsTestable.isAltTabEraVersion(version), version)
        }
    }

    func testAltTabVersionsAreAltTabEra() throws {
        for version in ["1.0.0", "5.1.0", "6.18.1", "9.0.0", "10.12.0"] {
            XCTAssertTrue(PreferencesMigrationsTestable.isAltTabEraVersion(version), version)
        }
    }

    /// the regression this guards. A 0.x plist compares numerically below every legacy threshold, so
    /// the whole chain looks pending — and it is re-evaluated on every launch, because migratePreferences
    /// writes App.version back into the plist each time. Several of those migrations are not idempotent:
    /// migrateShowWindowlessApps collapses 2 into 1, migratePreferencesIndexes flips titleTruncation 0<->2,
    /// migrateCursorFollowFocus overwrites the user's dropdown choice.
    func testForkVersionMatchesEveryLegacyThresholdAndSoMustNotEnterTheChain() throws {
        for threshold in Self.legacyThresholds {
            XCTAssertTrue(PreferencesMigrationsTestable.shouldRun("0.4.0", threshold), threshold)
        }
        XCTAssertFalse(PreferencesMigrationsTestable.isAltTabEraVersion("0.4.0"))
    }

    func testShouldRunOnlyForPlistsAtOrBelowTheThreshold() throws {
        XCTAssertTrue(PreferencesMigrationsTestable.shouldRun("9.0.0", "10.2.0"))
        XCTAssertTrue(PreferencesMigrationsTestable.shouldRun("10.2.0", "10.2.0"))
        XCTAssertFalse(PreferencesMigrationsTestable.shouldRun("10.12.0", "10.2.0"))
    }

    /// AltTab's last release is already on the newest schema, so importing its prefs must run nothing
    func testAltTabsLastReleaseNeedsNoLegacyMigration() throws {
        for threshold in Self.legacyThresholds {
            XCTAssertFalse(PreferencesMigrationsTestable.shouldRun("10.12.0", threshold), threshold)
        }
    }
}
