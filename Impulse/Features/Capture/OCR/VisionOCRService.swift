import Vision
import AppKit
import CoreImage

final class VisionOCRService: @unchecked Sendable {

    enum OCRError: LocalizedError {
        case imageConversionFailed
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .imageConversionFailed:
                return "图片转换失败"
            case .recognitionFailed(let reason):
                return "识别失败: \(reason)"
            }
        }
    }

    private let ciContext = CIContext()

    func recognizeText(from imageURL: URL, languages: [String] = ["zh-Hans", "en-US"]) async throws -> String {
        guard let image = NSImage(contentsOf: imageURL) else {
            throw OCRError.imageConversionFailed
        }

        return try await recognizeText(from: image, languages: languages)
    }

    func recognizeText(from image: NSImage, languages: [String] = ["zh-Hans", "en-US"]) async throws -> String {
        // 1. 预处理图片：增强对比度、灰度化，提升 OCR 准确率
        guard let preprocessedCGImage = preprocess(image) else {
            throw OCRError.imageConversionFailed
        }

        return try await Task.detached(priority: .userInitiated) {
            try await withCheckedThrowingContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    if let error = error {
                        continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                        return
                    }

                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: "")
                        return
                    }

                    let texts = observations.compactMap { observation in
                        observation.topCandidates(1).first?.string
                    }

                    continuation.resume(returning: texts.joined(separator: "\n"))
                }

                // 核心配置
                request.recognitionLevel = .accurate // 准确模式优先
                request.usesLanguageCorrection = true // 开启语言纠错
                request.recognitionLanguages = languages

                let handler = VNImageRequestHandler(cgImage: preprocessedCGImage, options: [:])

                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                }
            }
        }.value
    }

    /// 对屏幕截图进行预处理：缩放、灰度化、增强对比度
    private func preprocess(_ image: NSImage) -> CGImage? {
        guard let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }

        // 1. 灰度化过滤器
        let grayscale = CIFilter(name: "CIPhotoEffectMono")
        grayscale?.setValue(ciImage, forKey: kCIInputImageKey)
        
        // 2. 增强对比度过滤器 (让文字与背景更分明)
        let contrast = CIFilter(name: "CIColorControls")
        contrast?.setValue(grayscale?.outputImage, forKey: kCIInputImageKey)
        contrast?.setValue(1.1, forKey: kCIInputContrastKey) // 略微增加对比度
        contrast?.setValue(0.05, forKey: kCIInputBrightnessKey) // 略微增加亮度补偿
        
        // 3. 锐化 (让字符边缘更清晰)
        let sharpen = CIFilter(name: "CISharpenLuminance")
        sharpen?.setValue(contrast?.outputImage, forKey: kCIInputImageKey)
        sharpen?.setValue(0.8, forKey: kCIInputSharpnessKey)

        guard let outputCIImage = sharpen?.outputImage else { return nil }
        
        // 渲染回 CGImage
        return ciContext.createCGImage(outputCIImage, from: outputCIImage.extent)
    }
}
