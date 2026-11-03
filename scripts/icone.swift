// Gera Resources/AppIcon.icns: onda sonora branca sobre gradiente, no formato de ícone do macOS.
// Uso: swift scripts/icone.swift
import AppKit

let lado: CGFloat = 1024
let imagem = NSImage(size: NSSize(width: lado, height: lado), flipped: false) { _ in
    let margem = lado * 0.1  // área de respiro padrão dos ícones do macOS
    let caixa = NSRect(x: margem, y: margem, width: lado - 2 * margem, height: lado - 2 * margem)
    let forma = NSBezierPath(roundedRect: caixa, xRadius: caixa.width * 0.225, yRadius: caixa.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.36, green: 0.30, blue: 0.98, alpha: 1),
                        NSColor(red: 0.78, green: 0.27, blue: 0.85, alpha: 1)])!.draw(in: forma, angle: -60)
    let config = NSImage.SymbolConfiguration(pointSize: caixa.width * 0.5, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let simbolo = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    simbolo.draw(in: NSRect(x: caixa.midX - simbolo.size.width / 2, y: caixa.midY - simbolo.size.height / 2,
                            width: simbolo.size.width, height: simbolo.size.height))
    return true
}

let pasta = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: pasta)
try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
for tamanho in [16, 32, 128, 256, 512] {
    for escala in [1, 2] {
        let px = tamanho * escala
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        imagem.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let nome = "icon_\(tamanho)x\(tamanho)\(escala == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: pasta.appendingPathComponent(nome))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", pasta.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Resources/AppIcon.icns gerado" : "iconutil falhou")
