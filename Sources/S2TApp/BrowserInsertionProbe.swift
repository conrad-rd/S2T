import AppKit
import WebKit
import S2TCore

@MainActor enum BrowserInsertionProbe {
    static func run() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.makeFirstResponder(web)
        defer { web.stopLoading(); window.contentView = nil }
        web.loadHTMLString("""
        <html><body><div id="rich" contenteditable="true"></div><textarea id="plain"></textarea>
        <script>window.submissions=0;document.addEventListener('keydown',e=>{
        if(e.key==='Enter'&&!e.shiftKey){window.submissions++;e.preventDefault();}});</script>
        </body></html>
        """, baseURL: nil)
        for _ in 0..<500 {
            if !web.isLoading { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard !web.isLoading else { throw ServiceError.message("Generated browser fixture did not load.") }
        let words = "I like the processing animation, like here, or like here. Zoom in here showing the notch. Keep the logo and remove the subtitle. Change the CSS. Grüße 日本語 👩🏽‍💻 e\u{301}. "
        let text = String(repeating: words, count: 4).trimmingCharacters(in: .whitespaces) + "\n\n[Visual references · Prompt set fixture]\nReference 1, at 43.5s: The surrounding panel. Image: fixture-reference-1.png\nReference 2, at 48.0s: The notch. Image: fixture-reference-2.png"
        for target in ["rich", "plain"] {
            _ = try await web.evaluateJavaScript("document.getElementById('\(target)').focus()")
            web.insertText(text)
            var actual = ""
            for _ in 0..<100 {
                actual = try await web.evaluateJavaScript("document.getElementById('\(target)').\(target == "rich" ? "innerText" : "value")") as? String ?? ""
                if actual == text { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let submissions = try await web.evaluateJavaScript("window.submissions") as? Int ?? -1
            print("Browser \(target) fixture: expected \(text.utf16.count), received \(actual.utf16.count), submissions \(submissions).")
            if let mismatch = zip(actual.utf16, text.utf16).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
                print("Fixture mismatch at \(mismatch.offset): received \(mismatch.element.0), expected \(mismatch.element.1).")
            }
            guard Array(actual.utf16) == Array(text.utf16), submissions == 0,
                  !window.isVisible else { throw ServiceError.message("Browser \(target) editor changed or submitted the generated prompt.") }
        }
        print("Browser insertion: complete multiline prompt, reference order, Unicode and no submission PASS in hidden WebKit rich/plain editors using a single native text insertion. No user browser, screen pixels, real fields or clipboard used.")
    }
}
