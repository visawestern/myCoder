import XCTest
import SwiftUI
import AppKit
@testable import myCoder

/// Guards the chat code spoiler against vertical truncation. The user saw a
/// block whose header said "12 строк" while the expanded body stopped after
/// seven lines with an ellipsis. A `Text` with `fixedSize(vertical: false)`
/// shrinks — and truncates — whenever it is handed a short height, and the
/// nested horizontal `ScrollView` was not forced to its content height, so a
/// stale/clipped proposal could leave half the block hidden.
final class CodeBlockSpoilerLayoutTests: XCTestCase {

    private let code = """
    # Пример: запрос к Gaia TAP (ADQL) — первые 1000 звёзд с параллаксом > 10 мас
    from astroquery.gaia import Gaia
    Gaia.MAIN_GAIA_TABLE = "gaiadr3.gaia_source"

    job = Gaia.launch_job_async(\"\"\"
        SELECT source_id, ra, dec, parallax, phot_g_mean_mag, bp_rp
        FROM gaiadr3.gaia_source
        WHERE parallax > 10
        LIMIT 1000
    \"\"\")
    df = job.get_results().to_pandas()
    df.to_parquet("gaia_sample.parquet")
    """

    private var lineCount: Int { code.components(separatedBy: "\n").count }

    /// Lower bound for a full block: 12 lines of the default 12pt monospaced
    /// font (SwiftUI uses ~15pt per line) plus the 10pt body padding. A
    /// truncated seven-line block lands around 125pt.
    private var minimumBodyHeight: CGFloat { CGFloat(lineCount) * 13 }

    private var windows: [NSWindow] = []

    override func tearDown() {
        // Detach SwiftUI while every window is still strongly retained. Do
        // not leave delayed window work for a later async XCTest's run loop.
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        super.tearDown()
    }

    /// SwiftUI only performs scroll-view layout inside a window, so every
    /// sample gets an offscreen window of the requested size.
    private func host<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> NSHostingView<V> {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        windows.append(window)
        return host
    }

    /// Height of the document inside every horizontal scroll view in the tree.
    private func horizontalScrollDocumentHeights(in view: NSView) -> [CGFloat] {
        var result: [CGFloat] = []
        if String(describing: type(of: view)).contains("HostingScrollView"),
           let clip = view.subviews.first(where: { $0 is NSClipView }),
           let document = (clip as? NSClipView)?.documentView {
            result.append(document.frame.height)
        }
        for sub in view.subviews { result.append(contentsOf: horizontalScrollDocumentHeights(in: sub)) }
        return result
    }

    private func tallestDocument(in host: NSView) -> CGFloat {
        horizontalScrollDocumentHeights(in: host).max() ?? 0
    }

    func testWindowFixtureUsesExplicitLifetimeWithoutAnimations() {
        _ = host(Text("fixture"), width: 200, height: 100)
        guard let window = windows.last else {
            XCTFail("Window fixture was not retained")
            return
        }
        XCTAssertFalse(window.isReleasedWhenClosed, "ARC owns the fixture; close must not release it a second time")
        XCTAssertEqual(window.animationBehavior, .none, "Window fixture must not schedule transform animations")
    }

    func testExpandedSpoilerRendersEveryLine() {
        let host = host(
            CodeBlockSpoilerView(language: "python", code: code)
                .environment(\.codeDisplaySettings, .default),
            width: 620,
            height: 900
        )
        XCTAssertGreaterThanOrEqual(
            tallestDocument(in: host),
            minimumBodyHeight,
            "expanded spoiler must render all \(lineCount) lines"
        )
    }

    /// The regression itself: when the surrounding layout hands the spoiler a
    /// short height (the chat list can do this while a row is being re-measured
    /// mid-stream), the body must still lay out at its real height instead of
    /// truncating the code to the proposal.
    func testExpandedSpoilerIgnoresShortHeightProposal() {
        let host = host(
            VStack(spacing: 0) {
                CodeBlockSpoilerView(language: "python", code: code)
                    .environment(\.codeDisplaySettings, .default)
            }
            .frame(height: 120, alignment: .top),
            width: 620,
            height: 900
        )
        XCTAssertGreaterThanOrEqual(
            tallestDocument(in: host),
            minimumBodyHeight,
            "a short height proposal must not truncate the code body"
        )
    }

    func testExpandedSpoilerInsideChatListRendersEveryLine() {
        let message = Message(
            role: .assistant,
            content: "Here you go:\n\n```python\n\(code)\n```\n",
            parts: [.text("Here you go:\n\n```python\n\(code)\n```\n")],
            isFinished: true
        )
        let chat = ScrollView {
            LazyVStack(spacing: 16) {
                MessageRow(message: message)
                MessageRow(message: Message(role: .user, content: "thanks"))
            }
            .padding(.vertical, 16)
        }
        .environment(\.codeDisplaySettings, .default)

        let host = host(chat, width: 820, height: 640)
        XCTAssertGreaterThanOrEqual(
            tallestDocument(in: host),
            minimumBodyHeight,
            "chat spoiler must render all \(lineCount) lines"
        )
    }
}
