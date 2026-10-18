import AppKit
func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }

// Check the actual alpha geometry, not just whether an image has four channels.
func check(_ bitmap: NSBitmapImageRep, label: String) {
    let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
    guard bitmap.hasAlpha, w >= 16, h >= 16 else { fail("\(label): icon has no alpha channel") }
    let probes = [(0,0), (w-1,0), (0,h-1), (w-1,h-1),
                  (w/2,0), (w/2,h-1), (0,h/2), (w-1,h/2),
                  (w/10,h/10), (9*w/10,h/10), (w/10,9*h/10), (9*w/10,9*h/10)]
    for (x,y) in probes {
        guard let color = bitmap.colorAt(x:x, y:y), color.alphaComponent <= 0.04 else {
            fail("\(label): opaque exterior at \(x),\(y)")
        }
    }
    guard let center = bitmap.colorAt(x:w/2,y:h/2), center.alphaComponent >= 0.95 else {
        fail("\(label): icon center lost opacity")
    }
    print("PASS \(label): \(w)x\(h), transparent border and rounded corners, opaque center")
}

let args = CommandLine.arguments
if args.count == 4 && args[1] == "--bundle" {
    let image = NSWorkspace.shared.icon(forFile: args[2])
    guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:data),
          let png = bitmap.representation(using:.png, properties:[:]) else { fail("Cannot read native bundle icon") }
    check(bitmap,label:"native bundle icon")
    try png.write(to:URL(fileURLWithPath:args[3]))
} else {
    for path in args.dropFirst() {
        guard let image = NSImage(contentsOfFile:path) else { fail("Cannot load \(path)") }
        var count = 0
        for case let bitmap as NSBitmapImageRep in image.representations {
            check(bitmap,label:URL(fileURLWithPath:path).lastPathComponent); count += 1
        }
        guard count > 0 else { fail("No bitmap representations in \(path)") }
    }
}
