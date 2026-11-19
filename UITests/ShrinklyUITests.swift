import XCTest
import UIKit

/// Opens each screen on a device rotated to landscape and saves a screenshot of it. Each test fails when the app window does
/// not end up wider than tall, so a rotation that silently did not happen can never pass. Run by the landscape CI jobs.
final class LandscapeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    /// The simulator hands back its portrait frame buffer with a landscape picture lying on its side, so turn it upright.
    private func uprightScreenshot() -> UIImage {
        let source: UIImage = XCUIScreen.main.screenshot().image
        let sourceFormat = UIGraphicsImageRendererFormat()
        sourceFormat.scale = source.scale
        let image: UIImage = UIGraphicsImageRenderer(size: source.size, format: sourceFormat).image { _ in source.draw(at: .zero) }
        guard image.size.height > image.size.width else { return image }
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.rotate(by: -.pi / 2)
            image.draw(at: .zero)
        }
    }

    private func check(_ screen: String, settle: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        app.launchArguments = ["-skScreen", screen]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30), "No app window for \(screen)", file: file, line: line)
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline, window.frame.width <= window.frame.height {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(settle))

        let frame = window.frame
        let shot = XCTAttachment(image: uprightScreenshot())
        shot.name = "landscape-\(screen)"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertGreaterThan(frame.width, frame.height, "\(screen): window is \(Int(frame.width))x\(Int(frame.height)), not landscape", file: file, line: line)
        XCTAssertTrue(app.state == .runningForeground, "\(screen): app left the foreground", file: file, line: line)
        app.terminate()
    }

    func testHome() { check("home") }
    func testHomeFilled() { check("home-filled") }
    func testSetup() { check("setup") }
    func testSetupTarget() { check("setup-target") }
    func testSetupAdvanced() { check("setup-advanced") }
    func testProcessing() { check("processing") }
    func testSettings() { check("settings") }
    func testFormats() { check("formats") }
}

/// The real first-run path in portrait: Home, a sample clip, the setup screen, a compression, the result with its actions.
final class FirstRunUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSampleToResult() {
        XCUIDevice.shared.orientation = .portrait
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Ask App Not to Track", "Don’t Allow", "Don't Allow", "Not Now", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = ["-skNoAds", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["chooseVideos"].waitForExistence(timeout: 30), "Home has no Choose videos button")
        XCTAssertTrue(app.buttons["importFiles"].exists, "Home has no Import from Files button")
        let sample = app.buttons["trySample"]
        XCTAssertTrue(sample.exists, "Home has no sample clip button")
        sample.tap()

        let compress = app.buttons["compressButton"]
        XCTAssertTrue(compress.waitForExistence(timeout: 40), "Setup did not open after choosing the sample clip")
        XCTAssertTrue(app.staticTexts["estimateText"].exists, "Setup shows no size estimate")
        let whatsapp = app.buttons["preset-whatsapp"]
        XCTAssertTrue(whatsapp.exists, "Setup has no WhatsApp preset")
        whatsapp.tap()
        compress.tap()

        let saved = app.staticTexts["savedText"]
        XCTAssertTrue(saved.waitForExistence(timeout: 240), "Compression did not finish with a result")
        XCTAssertTrue(app.buttons["saveToPhotos"].exists, "Result has no Save to Photos button")
        XCTAssertTrue(app.buttons["share"].exists, "Result has no Share button")
        XCTAssertTrue(app.buttons["saveToFiles"].exists, "Result has no Save to Files button")

        let shot = XCTAttachment(image: XCUIScreen.main.screenshot().image)
        shot.name = "result"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSettingsOpensAndCloses() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-skNoAds", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 30))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10), "Settings has no Done button")
        XCTAssertTrue(app.buttons["licencesRow"].exists || app.staticTexts["Licences and source code"].exists, "Settings has no licences row")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["chooseVideos"].waitForExistence(timeout: 10))
    }
}
