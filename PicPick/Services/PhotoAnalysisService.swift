//
//  PhotoAnalysisService.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation
import Vision
import CoreImage
import Accelerate

/// 本地照片分析服务 - 特征向量提取、余弦相似度、模糊度检测
/// 全程在设备本地运行，不上传任何数据
final class PhotoAnalysisService {

    // MARK: - 阈值常量

    /// 相似照片判定阈值：余弦相似度 >= 0.85 归为相似组
    static let similarityThreshold: Float = 0.85

    /// 模糊判定阈值：Laplacian 方差低于该值视为模糊照片
    /// （256px 缩略图上的经验值，如需收紧/放宽可调整）
    static let blurVarianceThreshold: Double = 50.0

    // MARK: - 特征向量提取

    /// 使用 Vision 的 VNGenerateImageFeaturePrintRequest 提取特征向量
    /// 返回 2048 维 float 特征向量，失败返回 nil
    func extractFeatureVector(from cgImage: CGImage) throws -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { return nil }
        return observation.floatVector
    }

    // MARK: - 余弦相似度

    /// 计算两个特征向量的余弦相似度（vDSP 加速）
    /// 返回 [-1, 1]，越接近 1 越相似
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        let count = vDSP_Length(a.count)

        vDSP_dotpr(a, 1, b, 1, &dot, count)
        vDSP_dotpr(a, 1, a, 1, &normA, count)
        vDSP_dotpr(b, 1, b, 1, &normB, count)

        guard normA > 0, normB > 0 else { return 0 }
        return dot / (sqrt(normA) * sqrt(normB))
    }

    // MARK: - 模糊检测

    /// 使用 Core Image Laplacian 方差算法检测模糊度
    /// 返回值越小越模糊；低于 blurVarianceThreshold 视为模糊照片
    func laplacianVariance(of cgImage: CGImage) -> Double? {
        let ciImage = CIImage(cgImage: cgImage)

        guard let laplacianFilter = CIFilter(name: "CILaplacian") else { return nil }
        laplacianFilter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let laplacianOutput = laplacianFilter.outputImage else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])

        // 缩小到约 256px 计算方差（性能与精度平衡）
        let extent = laplacianOutput.extent
        let scale = min(1.0, 256.0 / max(extent.width, extent.height))
        let scaled = laplacianOutput.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let rendered = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        guard let pixels = grayscalePixels(of: rendered), !pixels.isEmpty else { return nil }

        // 灰度均值 + 方差
        let mean = pixels.reduce(0.0, +) / Double(pixels.count)
        let variance = pixels.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(pixels.count)
        return variance
    }

    /// 读取 CGImage 灰度像素（0-255，Rec.601 亮度近似）
    private func grayscalePixels(of cgImage: CGImage) -> [Double]? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels: [Double] = []
        pixels.reserveCapacity(width * height)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            let r = Double(rgba[index])
            let g = Double(rgba[index + 1])
            let b = Double(rgba[index + 2])
            pixels.append(0.299 * r + 0.587 * g + 0.114 * b)
        }
        return pixels
    }
}

// MARK: - Vision 扩展

extension VNFeaturePrintObservation {
    /// 提取特征向量（Vision 返回的 float32 数组，通常 2048 维）
    /// 说明：Vision 也提供 computeDistance(_:) 直接比较两张图（内部等价于余弦距离），
    /// 此处提取原始向量以显式实现余弦相似度阈值（0.85）判断
    var floatVector: [Float]? {
        guard let data = self.data,
              elementType == .float,
              data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }
}
