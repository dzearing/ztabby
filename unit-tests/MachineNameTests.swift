import XCTest

final class MachineNameTests: XCTestCase {
    private let aliases = MachineNameTestable.aliases(["Davids-Personal-Macbook-Pro.local", "David's Personal Macbook Pro"])

    func testLoopbackNamesAreLocal() throws {
        XCTAssertTrue(MachineNameTestable.isLocal("localhost", aliases))
        XCTAssertTrue(MachineNameTestable.isLocal("127.0.0.1", aliases))
        XCTAssertTrue(MachineNameTestable.isLocal("::1", aliases))
        XCTAssertTrue(MachineNameTestable.isLocal("Local", aliases))
    }

    func testHostNameIsLocalWithOrWithoutLocalSuffix() throws {
        XCTAssertTrue(MachineNameTestable.isLocal("Davids-Personal-Macbook-Pro.local", aliases))
        XCTAssertTrue(MachineNameTestable.isLocal("davids-personal-macbook-pro", aliases))
        XCTAssertTrue(MachineNameTestable.isLocal("  DAVID'S PERSONAL MACBOOK PRO ", aliases))
    }

    func testRemoteMachinesAreNotLocal() throws {
        XCTAssertFalse(MachineNameTestable.isLocal("Home PC", aliases))
        XCTAssertFalse(MachineNameTestable.isLocal("192.168.1.20", aliases))
        XCTAssertFalse(MachineNameTestable.isLocal("", aliases))
    }

    func testNormalizeFoldsAliasesAndKeepsRemoteNames() throws {
        XCTAssertEqual(MachineNameTestable.normalize("localhost"), MachineNameTestable.localMachineName)
        XCTAssertEqual(MachineNameTestable.normalize("127.0.0.1"), MachineNameTestable.localMachineName)
        XCTAssertEqual(MachineNameTestable.normalize("Home PC"), "Home PC")
        XCTAssertNil(MachineNameTestable.normalize(nil))
    }
}
