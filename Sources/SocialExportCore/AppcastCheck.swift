import Foundation

/// Pure helpers for the extension's update nudge: parse a Sparkle appcast, decide when to re-check, build the text.
public enum AppcastCheck {
    public static let feedURL = URL(string: "https://apps.tonalphoto.com/social-export/appcast.xml")!
    public static let interval: TimeInterval = 86_400
    public static let nudge = " · Update available: open Social Export"

    /// Highest numeric `sparkle:version` (build number) across all items, read from either the
    /// `<sparkle:version>` element or the enclosure's `sparkle:version` attribute. Nil for malformed or empty feeds.
    public static func latestBuild(in data: Data) -> Int? {
        let parser = XMLParser(data: data)
        let collector = VersionCollector()
        parser.delegate = collector
        guard parser.parse() else { return nil }
        return collector.builds.max()
    }

    public static func shouldCheck(now: Date, lastCheck: Date?) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    public static func nudgeText(current: Int, latest: Int?) -> String? {
        guard let latest, latest > current else { return nil }
        return nudge
    }
}

private final class VersionCollector: NSObject, XMLParserDelegate {
    var builds: [Int] = []
    private var inVersionElement = false
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "sparkle:version" {
            inVersionElement = true
            text = ""
        } else if elementName == "enclosure", let v = attributes["sparkle:version"], let n = Int(v) {
            builds.append(n)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inVersionElement { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "sparkle:version" else { return }
        inVersionElement = false
        if let n = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) { builds.append(n) }
    }
}
