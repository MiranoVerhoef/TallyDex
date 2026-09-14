import XCTest
@testable import ScanLabCore

final class ScanLabCoreTests: XCTestCase {
    func testRegionValidity() {
        XCTAssertTrue(CardRegion(x: 0.1, y: 0.1, width: 0.5, height: 0.7).valid)
        XCTAssertFalse(CardRegion(x: .nan, y: 0, width: 0.3, height: 0.3).valid)
        XCTAssertFalse(CardRegion(x: 0.8, y: 0, width: 0.3, height: 0.3).valid)
    }
    func testGateSuppressesJitterAndRearmsNewPose() {
        var gate = CaptureGate()
        let first = CardRegion(x: 0.1, y: 0.1, width: 0.3, height: 0.5)
        XCTAssertFalse(gate.observe(first, at: 0))
        XCTAssertTrue(gate.observe(first, at: 0.9))
        XCTAssertFalse(gate.observe(first, at: 10))
        XCTAssertFalse(gate.observe(CardRegion(x: 0.11, y: 0.1, width: 0.3, height: 0.5), at: 11))
        let next = CardRegion(x: 0.4, y: 0.2, width: 0.3, height: 0.5)
        XCTAssertFalse(gate.observe(next, at: 12))
        XCTAssertTrue(gate.observe(next, at: 13))
    }
    func testShortMissingFrameDoesNotDuplicate() {
        var gate = CaptureGate()
        let box = CardRegion(x: 0.1, y: 0.1, width: 0.3, height: 0.5)
        XCTAssertFalse(gate.observe(box, at: 0)); XCTAssertTrue(gate.observe(box, at: 1))
        XCTAssertFalse(gate.observe(nil, at: 1.1)); XCTAssertFalse(gate.observe(box, at: 4))
        XCTAssertFalse(gate.observe(nil, at: 5)); XCTAssertFalse(gate.observe(nil, at: 6.3))
        XCTAssertFalse(gate.observe(box, at: 7)); XCTAssertTrue(gate.observe(box, at: 8))
    }
    func testCRC() { XCTAssertEqual(StoredZIP.crc32(Data("123456789".utf8)), 0xcbf43926) }
    func testContentChangeRearmsOnlyOnceForStableNewAppearance() {
        var gate = ContentChangeGate()
        gate.markSaved([0.1,0.1,0.1], at: 0)
        XCTAssertFalse(gate.observe([0.11,0.1,0.1], at: 4))
        XCTAssertFalse(gate.observe([0.5,0.5,0.5], at: 5))
        XCTAssertFalse(gate.observe([0.5,0.5,0.5], at: 5.5))
        XCTAssertTrue(gate.observe([0.5,0.5,0.5], at: 5.8))
        XCTAssertFalse(gate.observe([0.5,0.5,0.5], at: 10))
        gate.markSaved([0.5,0.5,0.5], at: 10)
        XCTAssertFalse(gate.observe([0.5,0.5,0.5], at: 20))
    }
    @MainActor func testReviewedOnlyAndSyntheticTrainingOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScanLabTest-" + UUID().uuidString)
        let store = DatasetStore(root: root), goal = CaptureGoal.all[0]
        let region = CardRegion(x: 0.1, y: 0.1, width: 0.4, height: 0.6)
        try store.add(jpeg: Data([1,2,3]), width: 100, height: 200, goal: goal, session: UUID(), region: region)
        XCTAssertEqual(store.count(goal), 0)
        try store.review(id: store.samples[0].id, kind: .front, region: region)
        XCTAssertEqual(store.count(goal), 1)
        try store.add(jpeg: Data([1,2]), width: 100, height: 200, goal: CaptureGoal.all.last!, session: UUID(), region: region, source: .synthetic)
        XCTAssertEqual(store.samples.last?.split, .training)
        XCTAssertEqual(store.count(CaptureGoal.all.last!), 0)
        let zip = try store.export()
        let bytes = try Data(contentsOf: zip)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-t", zip.path]; try task.run(); task.waitUntilExit()
        XCTAssertEqual(task.terminationStatus, 0)
        XCTAssertEqual(DatasetStore(root: root).samples.count, 2)
    }
    @MainActor func testBadMetadataNeverOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScanLabBad-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let metadata = root.appendingPathComponent("samples.json")
        let original = Data("broken metadata".utf8); try original.write(to: metadata)
        let store = DatasetStore(root: root)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.add(jpeg: Data([1]), width: 1, height: 1, goal: CaptureGoal.all[0], session: UUID(), region: nil))
        XCTAssertEqual(try Data(contentsOf: metadata), original)
    }
    @MainActor func testBackgroundHasNoBoxesAndInvalidFrontCannotApprove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScanLabNegative-" + UUID().uuidString)
        let store = DatasetStore(root: root)
        try store.add(jpeg: Data([1]), width: 10, height: 20, goal: CaptureGoal.all[5], session: UUID(), region: nil)
        let id = store.samples[0].id
        XCTAssertThrowsError(try store.review(id: id, kind: .front, region: nil))
        try store.review(id: id, kind: .background, region: nil)
        XCTAssertTrue(store.samples[0].exportable)
        try store.review(id: id, kind: .front, region: nil, exclude: true)
        XCTAssertFalse(store.samples[0].exportable)
    }
}
