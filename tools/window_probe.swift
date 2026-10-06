// Finds the CodexBridger window so the screenshot harness can capture just that
// window instead of the whole desktop. Prints "<windowID> <x> <y> <w> <h>".
import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write("could not read the window list\n".data(using: .utf8)!)
    exit(2)
}

for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.contains("CodexBridger") else { continue }
    guard let number = window[kCGWindowNumber as String] as? Int else { continue }
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let x = bounds["X"] as? Double ?? 0
    let y = bounds["Y"] as? Double ?? 0
    let w = bounds["Width"] as? Double ?? 0
    let h = bounds["Height"] as? Double ?? 0
    // Skip tiny helper windows; we want the document window.
    if w < 400 || h < 300 { continue }
    print("\(number) \(Int(x)) \(Int(y)) \(Int(w)) \(Int(h))")
    exit(0)
}
FileHandle.standardError.write("no CodexBridger window found\n".data(using: .utf8)!)
exit(1)
