import ApplicationServices

/// Dünne Hülle um die C-API der Bedienungshilfen.
enum AX {
    static func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ e: AXUIElement, _ name: String) -> String? {
        guard let v = attribute(e, name) else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func number(_ e: AXUIElement, _ name: String) -> Double? {
        (attribute(e, name) as? NSNumber)?.doubleValue
    }

    static func role(_ e: AXUIElement) -> String? { string(e, kAXRoleAttribute) }

    static func children(_ e: AXUIElement) -> [AXUIElement] {
        (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func parent(_ e: AXUIElement) -> AXUIElement? {
        guard let v = attribute(e, kAXParentAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func windows(of app: AXUIElement) -> [AXUIElement] {
        (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    /// Rahmen in globalen Quartz-Koordinaten (Ursprung oben links am Hauptbildschirm).
    static func frame(_ e: AXUIElement) -> CGRect? {
        guard let pv = attribute(e, kAXPositionAttribute), let sv = attribute(e, kAXSizeAttribute),
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// Rahmen des tatsächlich gezeichneten Texts (Quartz-Koordinaten) – das Textfeld selbst ist oft breiter.
    static func textBounds(_ e: AXUIElement) -> CGRect? {
        guard let count = number(e, kAXNumberOfCharactersAttribute), count > 0 else { return nil }
        var range = CFRange(location: 0, length: Int(count))
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(e, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         rangeValue, &result) == .success,
              let value = result, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0 else { return nil }
        return rect
    }

    static func findAll(_ e: AXUIElement, role wanted: String, maxDepth: Int = 8, depth: Int = 0) -> [AXUIElement] {
        var out: [AXUIElement] = []
        if role(e) == wanted { out.append(e) }
        guard depth < maxDepth else { return out }
        for c in children(e) { out += findAll(c, role: wanted, maxDepth: maxDepth, depth: depth + 1) }
        return out
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Zeigt den System-Dialog, der zu den Bedienungshilfen-Einstellungen führt.
    static func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
