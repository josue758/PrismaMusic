import AppKit
let destination = CommandLine.arguments[1]
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 42, y: 42, width: 940, height: 940)
let shape = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [NSColor(red: 0.045, green: 0.07, blue: 0.16, alpha: 1), NSColor(red: 0.26, green: 0.12, blue: 0.48, alpha: 1)])!
gradient.draw(in: shape, angle: -50)
NSColor.white.withAlphaComponent(0.18).setStroke(); shape.lineWidth = 3; shape.stroke()
let colors: [NSColor] = [.systemCyan, .systemPurple, .systemPink]
for i in 0..<7 {
    let radius = CGFloat(i) * 28
    let ring = NSBezierPath(ovalIn: NSRect(x: 235-radius/2, y: 330-radius/2, width: 550+radius, height: 350+radius))
    colors[i % 3].withAlphaComponent(0.3).setStroke(); ring.lineWidth = 4; ring.stroke()
}
let wave = NSBezierPath()
for i in 0...240 {
    let x = CGFloat(i)/240*520+252
    let t = Double(i)/240
    let envelope = pow(sin(t * .pi), 2)
    let y = 510 + sin(t * .pi * 10)*envelope*155
    if i == 0 { wave.move(to: NSPoint(x:x,y:y)) } else { wave.line(to: NSPoint(x:x,y:y)) }
}
NSColor.white.setStroke(); wave.lineWidth = 20; wave.lineCapStyle = .round; wave.stroke()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
