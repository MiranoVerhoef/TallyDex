import XCTest
import ImageIO
import UIKit
@testable import ScanLab
final class ScanLabIOSTests: XCTestCase {
    @MainActor func testBundledArtCanGenerateValidTrainingImage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScanLabIOS-" + UUID().uuidString)
        let store = DatasetStore(root: root)
        let generator = ExampleGenerator()
        generator.generate(count: 10, store: store)
        for _ in 0..<200 {
            if !generator.running { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(generator.error)
        XCTAssertFalse(generator.running)
        XCTAssertEqual(store.samples.count, 10)
        XCTAssertEqual(store.count(CaptureGoal.all[0]), 0)
        for sample in store.samples {
            XCTAssertTrue(sample.exportable); XCTAssertEqual(sample.source, .synthetic)
            XCTAssertEqual(sample.split, .training); XCTAssertTrue(sample.region?.valid == true)
            let image = try XCTUnwrap(UIImage(contentsOfFile: store.imageURL(sample).path))
            XCTAssertEqual(image.size, CGSize(width: 960, height: 1280))
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 960, height: 1280))
        let black = renderer.image { context in UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 960, height: 1280)) }
        let jpeg = try XCTUnwrap(black.jpegData(compressionQuality: 0.8))
        try store.add(jpeg: jpeg, width: Int(black.size.width * black.scale), height: Int(black.size.height * black.scale), goal: CaptureGoal.all[5], session: UUID(), region: nil)
        let negative = try XCTUnwrap(store.samples.last)
        try store.review(id: negative.id, kind: .background, region: nil)
        XCTAssertEqual(store.count(CaptureGoal.all[5]), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.export().path))
    }
    func testAspectFitMapping() {
        let frame = fittedFrame(in: CGSize(width: 400, height: 400), aspect: 0.5)
        XCTAssertEqual(frame, CGRect(x: 100, y: 0, width: 200, height: 400))
    }
}
