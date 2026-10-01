// make_icon.swift：以 CoreGraphics 繪製 DockLens App 圖示（1024px），再由 make_icon.sh 縮成各尺寸
// 用法：swift scripts/make_icon.swift <輸出 png 路徑>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let squircle = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.45, blue: 1.0, alpha: 1), NSColor(red: 0.55, green: 0.25, blue: 0.95, alpha: 1)])!
        .draw(in: squircle, angle: -60)
    // 兩張疊放的視窗卡片
    func card(_ r: NSRect, alpha: CGFloat) {
        let p = NSBezierPath(roundedRect: r, xRadius: 40, yRadius: 40)
        NSColor.white.withAlphaComponent(alpha).setFill(); p.fill()
        let bar = NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.maxY - 70, width: r.width, height: 70), xRadius: 40, yRadius: 40)
        NSColor.white.withAlphaComponent(min(1, alpha + 0.2)).setFill(); bar.fill()
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: r.minX + 30 + CGFloat(i) * 42, y: r.maxY - 50, width: 28, height: 28)).fill()
        }
    }
    card(NSRect(x: 250, y: 400, width: 480, height: 330), alpha: 0.45)
    card(NSRect(x: 320, y: 300, width: 480, height: 330), alpha: 0.95)
    // Dock 列
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: 260, y: 190, width: 504, height: 60), xRadius: 30, yRadius: 30).fill()
    return true
}
let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
