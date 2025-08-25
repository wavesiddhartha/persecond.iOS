import Foundation
import AVFoundation
import UIKit
import CoreImage
import Combine

class VideoFrameExtractor: ObservableObject {
    
    @Published var extractionProgress: Double = 0.0
    @Published var isExtracting: Bool = false
    @Published var extractedFrames: [FrameAdjustment] = []
    
    private let imageGenerator = AVAssetImageGenerator(asset: AVAsset())
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupImageGenerator()
    }
    
    private func setupImageGenerator() {
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 1920, height: 1080)
    }
    
    func extractFrames(from asset: AVAsset, 
                      in range: ClosedRange<Double> = 0.0...1.0, 
                      maxFrames: Int = 120) async throws -> [FrameAdjustment] {
        
        await MainActor.run {
            isExtracting = true
            extractionProgress = 0.0
            extractedFrames.removeAll()
        }
        
        let duration = asset.duration
        let totalDuration = duration.seconds
        
        let startTime = totalDuration * range.lowerBound
        let endTime = totalDuration * range.upperBound
        let selectedDuration = endTime - startTime
        
        let frameInterval = selectedDuration / Double(maxFrames)
        var times: [NSValue] = []
        
        for i in 0..<maxFrames {
            let timeSeconds = startTime + (Double(i) * frameInterval)
            let time = CMTime(seconds: timeSeconds, preferredTimescale: duration.timescale)
            times.append(NSValue(time: time))
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1080)
        
        var frameAdjustments: [FrameAdjustment] = []
        var processedCount = 0
        
        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] (requestedTime, image, actualTime, result, error) in
                
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    processedCount += 1
                    self.extractionProgress = Double(processedCount) / Double(maxFrames)
                    
                    if let error = error {
                        print("Frame extraction error: \(error)")
                    } else if let cgImage = image {
                        let uiImage = UIImage(cgImage: cgImage)
                        let frameAdjustment = FrameAdjustment(
                            frameIndex: processedCount - 1,
                            timestamp: actualTime,
                            thumbnail: uiImage
                        )
                        frameAdjustments.append(frameAdjustment)
                        self.extractedFrames.append(frameAdjustment)
                    }
                    
                    if processedCount == maxFrames {
                        self.isExtracting = false
                        self.extractionProgress = 1.0
                        
                        frameAdjustments.sort { $0.frameIndex < $1.frameIndex }
                        continuation.resume(returning: frameAdjustments)
                    }
                }
            }
        }
    }
    
    func extractSingleFrame(from asset: AVAsset, at time: CMTime) async throws -> UIImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1080)
        
        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { (requestedTime, image, actualTime, result, error) in
                
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let cgImage = image {
                    let uiImage = UIImage(cgImage: cgImage)
                    continuation.resume(returning: uiImage)
                } else {
                    continuation.resume(throwing: NSError(domain: "VideoFrameExtractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract frame"]))
                }
            }
        }
    }
    
    func generateThumbnail(from asset: AVAsset, at time: CMTime? = nil, size: CGSize = CGSize(width: 300, height: 300)) async throws -> UIImage {
        let targetTime = time ?? CMTime(seconds: 1.0, preferredTimescale: 600)
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        
        let cgImage = try await generator.image(at: targetTime).image
        return UIImage(cgImage: cgImage)
    }
    
    func extractFramesSequentially(from asset: AVAsset, 
                                 times: [CMTime], 
                                 progressCallback: @escaping (Double) -> Void) async throws -> [FrameAdjustment] {
        
        await MainActor.run {
            isExtracting = true
            extractionProgress = 0.0
        }
        
        var frameAdjustments: [FrameAdjustment] = []
        
        for (index, time) in times.enumerated() {
            do {
                let image = try await extractSingleFrame(from: asset, at: time)
                let frameAdjustment = FrameAdjustment(
                    frameIndex: index,
                    timestamp: time,
                    thumbnail: image
                )
                frameAdjustments.append(frameAdjustment)
                
                await MainActor.run {
                    self.extractionProgress = Double(index + 1) / Double(times.count)
                    progressCallback(self.extractionProgress)
                }
            } catch {
                print("Failed to extract frame at time \(time): \(error)")
            }
        }
        
        await MainActor.run {
            isExtracting = false
            extractionProgress = 1.0
        }
        
        return frameAdjustments
    }
    
    func clearExtractedFrames() {
        extractedFrames.removeAll()
        extractionProgress = 0.0
        isExtracting = false
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }
}