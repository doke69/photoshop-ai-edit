import AppKit

// Native visual QA only: images are drawn unmasked over three opaque backgrounds.
let args = CommandLine.arguments
let output = args[1]
let entries = args.dropFirst(2).map { value -> (String, NSImage) in
    let pair = value.split(separator: "=", maxSplits: 1).map(String.init)
    guard pair.count == 2, let image = NSImage(contentsOfFile: pair[1]) else { exit(1) }
    return (pair[0], image)
}
let width = 1140, height = 114 + entries.count * 218
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.97, alpha: 1).setFill()
NSRect(x:0,y:0,width:width,height:height).fill()
func text(_ value:String, x:CGFloat, y:CGFloat, size:CGFloat, bold:Bool=false) {
    (value as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:bold ? NSFont.boldSystemFont(ofSize:size) : NSFont.systemFont(ofSize:size), .foregroundColor:NSColor(calibratedRed:0.09,green:0.15,blue:0.24,alpha:1)])
}
text("透明圆角图标 · 实际资源对照",x:24,y:CGFloat(height-45),size:25,bold:true)
text("图像本身无裁切或遮罩；同一图标同时展示 128px 和 48px。",x:24,y:CGFloat(height-75),size:14)
for (row,entry) in entries.enumerated() {
    let top = height - 110 - row * 218
    text(entry.0,x:24,y:CGFloat(top-18),size:16,bold:true)
    for col in 0..<3 {
        let rect = NSRect(x:24+col*372,y:top-190,width:348,height:154)
        if col == 0 { NSColor.white.setFill();rect.fill() }
        else if col == 1 { NSColor(calibratedRed:0.13,green:0.18,blue:0.26,alpha:1).setFill();rect.fill() }
        else {
            for y in stride(from:0,to:154,by:12) { for x in stride(from:0,to:348,by:12) {
                let light = ((x/12+y/12)%2)==0
                (light ? NSColor.white : NSColor(calibratedWhite:0.8,alpha:1)).setFill()
                NSRect(x:rect.minX+CGFloat(x),y:rect.minY+CGFloat(y),width:CGFloat(min(12,348-x)),height:CGFloat(min(12,154-y))).fill()
            } }
        }
        entry.1.draw(in:NSRect(x:rect.minX+50,y:rect.minY+13,width:128,height:128),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
        entry.1.draw(in:NSRect(x:rect.minX+232,y:rect.minY+53,width:48,height:48),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
    }
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output))
