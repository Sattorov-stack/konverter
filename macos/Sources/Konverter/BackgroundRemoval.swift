import AppKit
import Vision
import CoreImage

/// Удаление фона с фото встроенной нейросетью macOS (Vision), интернет не нужен
@MainActor
enum BackgroundRemoval {
    static func remove(_ src: URL) async throws -> URL {
        guard let image = NSImage(contentsOf: src),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ConvertError.msg("Не удалось открыть картинку")
        }
        let png: Data = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNGenerateForegroundInstanceMaskRequest()
                    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                    try handler.perform([request])
                    guard let obs = request.results?.first else {
                        throw ConvertError.msg("Не нашёл на фото главный объект")
                    }
                    let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
                    let ci = CIImage(cvPixelBuffer: buffer)
                    let context = CIContext()
                    guard let data = context.pngRepresentation(of: ci, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else {
                        throw ConvertError.msg("Не удалось сохранить PNG")
                    }
                    cont.resume(returning: data)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        let base = src.deletingPathExtension().lastPathComponent
        let out = Converter.uniqueOut(dir: Converter.outputDir(for: src), base: "\(base) (без фона)", ext: "png")
        try png.write(to: out)
        return out
    }
}
