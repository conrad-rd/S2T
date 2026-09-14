import Foundation

public enum TextReplacement {
    public static func apply(_ inserted: String, to original: String, selection: NSRange) -> String? {
        let source = original as NSString
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
              selection.location <= source.length, selection.length <= source.length - selection.location,
              isBoundary(selection.location, in: source),
              isBoundary(selection.location + selection.length, in: source) else { return nil }
        return source.replacingCharacters(in: selection, with: inserted)
    }
    private static func isBoundary(_ offset: Int, in text: NSString) -> Bool {
        guard offset > 0, offset < text.length else { return true }
        return !(0xDC00...0xDFFF).contains(text.character(at: offset))
            || !(0xD800...0xDBFF).contains(text.character(at: offset - 1))
    }
}
