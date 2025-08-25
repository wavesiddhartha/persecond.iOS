import Foundation
import AVFoundation
import CoreImage
import UIKit
import Combine

class VideoExporter: ObservableObject {
    
    @Published var exportProgress: Double = 0.0
    @Published var isExporting: Bool = false
    @Published var exportStatus: String = "Ready to export"
    @Published var exportError: Error?
    @Published var estimatedFileSize: Int64 = 0
    
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var assetWriterAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioAssetWriterInput: AVAssetWriterInput?
    
    private let imageProcessor: LiveImageProcessor
    private let renderQueue = DispatchQueue(label: "video.export.render", qos: .userInitiated)
    
    init(imageProcessor: LiveImageProcessor) {
        self.imageProcessor = imageProcessor
    }
    
    func exportVideo(project: VideoProject, 
                    exportSettings: ExportSettings, 
                    outputURL: URL) async throws {
        
        guard let originalAsset = project.asset else {
            throw ExportError.noOriginalAsset
        }
        
        await MainActor.run {
            isExporting = true
            exportProgress = 0.0
            exportStatus = "Preparing export..."
            exportError = nil
        }
        
        do {
            
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            
            
            try await setupAssetWriter(outputURL: outputURL, settings: exportSettings)
            
            
            try await processAndWriteFrames(project: project, originalAsset: originalAsset, settings: exportSettings)
            
            
            try await copyAudioTrack(from: originalAsset, settings: exportSettings)
            
            
            try await finalizeExport()
            
            await MainActor.run {
                isExporting = false
                exportStatus = "Export completed successfully"
                exportProgress = 1.0
            }
            
        } catch {
            await MainActor.run {
                isExporting = false
                exportError = error
                exportStatus = "Export failed: \(error.localizedDescription)"
            }
            
            cleanupAssetWriter()
            throw error
        }
    }
    
    private func setupAssetWriter(outputURL: URL, settings: ExportSettings) async throws {
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: settings.fileType)
        
        guard let assetWriter = assetWriter else {
            throw ExportError.failedToCreateAssetWriter
        }
        
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: settings.videoCodec,
            AVVideoWidthKey: settings.resolution.width,
            AVVideoHeightKey: settings.resolution.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.videoBitrate,
                AVVideoProfileLevelKey: settings.profileLevel,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]
        
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        assetWriterInput?.expectsMediaDataInRealTime = false
        assetWriterInput?.transform = settings.transform
        
        guard let assetWriterInput = assetWriterInput else {
            throw ExportError.failedToCreateVideoInput
        }
        
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: settings.resolution.width,
            kCVPixelBufferHeightKey as String: settings.resolution.height,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        guard assetWriter.canAdd(assetWriterInput) else {
            throw ExportError.cannotAddVideoInput
        }
        
        assetWriter.add(assetWriterInput)
        
        await MainActor.run {
            exportStatus = "Asset writer configured"
        }
    }
    
    private func processAndWriteFrames(project: VideoProject, 
                                     originalAsset: AVAsset, 
                                     settings: ExportSettings) async throws {
        
        guard let assetWriter = assetWriter,
              let assetWriterInput = assetWriterInput,
              let assetWriterAdaptor = assetWriterAdaptor else {
            throw ExportError.assetWriterNotConfigured
        }
        
        guard assetWriter.startWriting() else {
            throw ExportError.failedToStartWriting
        }
        
        assetWriter.startSession(atSourceTime: .zero)
        
        let selectedFrames = project.selectedFrames
        let totalFrames = selectedFrames.count
        let frameDuration = CMTime(value: 1, timescale: Int32(project.frameRate))
        
        await MainActor.run {
            exportStatus = "Processing \(totalFrames) frames..."
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            assetWriterInput.requestMediaDataWhenReady(on: renderQueue) { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: ExportError.exportCancelled)
                    return
                }
                
                var frameIndex = 0
                
                while assetWriterInput.isReadyForMoreMediaData && frameIndex < totalFrames {
                    let frame = selectedFrames[frameIndex]
                    let presentationTime = CMTime(value: Int64(frameIndex), timescale: Int32(project.frameRate))
                    
                    do {
                        let pixelBuffer = try self.createPixelBuffer(from: frame, settings: settings)
                        
                        if !assetWriterAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                            throw ExportError.failedToAppendPixelBuffer
                        }
                        
                        frameIndex += 1
                        
                        DispatchQueue.main.async {
                            self.exportProgress = Double(frameIndex) / Double(totalFrames) * 0.8
                            self.exportStatus = "Processing frame \(frameIndex) of \(totalFrames)"
                        }
                        
                    } catch {
                        assetWriterInput.markAsFinished()
                        continuation.resume(throwing: error)
                        return
                    }
                }
                
                if frameIndex >= totalFrames {
                    assetWriterInput.markAsFinished()
                    continuation.resume()
                } else {
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        
                    }
                }
            }
        }
    }
    
    private func createPixelBuffer(from frame: FrameAdjustment, settings: ExportSettings) throws -> CVPixelBuffer {
        guard let thumbnail = frame.thumbnail else {
            throw ExportError.missingFrameData
        }
        
        
        let ciImage = CIImage(image: thumbnail) ?? CIImage()
        let processedImage = imageProcessor.processImageSync(ciImage, adjustments: frame.adjustments)
        
        
        let scaledImage = processedImage.transformed(by: CGAffineTransform(
            scaleX: CGFloat(settings.resolution.width) / ciImage.extent.width,
            y: CGFloat(settings.resolution.height) / ciImage.extent.height
        ))
        
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(settings.resolution.width),
            Int(settings.resolution.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw ExportError.failedToCreatePixelBuffer
        }
        
        
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(scaledImage, to: buffer)
        
        return buffer
    }
    
    private func copyAudioTrack(from asset: AVAsset, settings: ExportSettings) async throws {
        guard let assetWriter = assetWriter,
              settings.includeAudio else { return }
        
        await MainActor.run {
            exportStatus = "Processing audio track..."
            exportProgress = 0.8
        }
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            
            return
        }
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: settings.audioSampleRate,
            AVNumberOfChannelsKey: settings.audioChannels,
            AVEncoderBitRateKey: settings.audioBitrate
        ]
        
        audioAssetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioAssetWriterInput?.expectsMediaDataInRealTime = false
        
        guard let audioInput = audioAssetWriterInput,
              assetWriter.canAdd(audioInput) else {
            return
        }
        
        assetWriter.add(audioInput)
        
        
        let audioReader = try AVAssetReader(asset: asset)
        let audioReaderOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM]
        )
        
        audioReader.add(audioReaderOutput)
        audioReader.startReading()
        
        return try await withCheckedThrowingContinuation { continuation in
            audioInput.requestMediaDataWhenReady(on: renderQueue) {
                while audioInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                    
                    if !audioInput.append(sampleBuffer) {
                        audioInput.markAsFinished()
                        continuation.resume(throwing: ExportError.failedToAppendAudioBuffer)
                        return
                    }
                }
            }
        }
    }
    
    private func finalizeExport() async throws {
        guard let assetWriter = assetWriter else {
            throw ExportError.assetWriterNotConfigured
        }
        
        await MainActor.run {
            exportStatus = "Finalizing export..."
            exportProgress = 0.95
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            assetWriter.finishWriting {
                if assetWriter.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: assetWriter.error ?? ExportError.unknownExportError)
                }
            }
        }
    }
    
    private func cleanupAssetWriter() {
        assetWriter?.cancelWriting()
        assetWriter = nil
        assetWriterInput = nil
        assetWriterAdaptor = nil
        audioAssetWriterInput = nil
    }
    
    func cancelExport() {
        guard isExporting else { return }
        
        cleanupAssetWriter()
        isExporting = false
        exportStatus = "Export cancelled"
        exportProgress = 0.0
    }
    
    func estimateFileSize(for project: VideoProject, settings: ExportSettings) -> Int64 {
        let selectedFrames = project.selectedFrames
        let duration = Double(selectedFrames.count) / project.frameRate
        
        let videoBitrate = Int64(settings.videoBitrate)
        let audioBitrate = settings.includeAudio ? Int64(settings.audioBitrate) : 0
        
        let totalBitrate = videoBitrate + audioBitrate
        let estimatedSize = Int64(duration * Double(totalBitrate) / 8.0)
        
        estimatedFileSize = estimatedSize
        return estimatedSize
    }
}

struct ExportSettings {
    let resolution: CGSize
    let frameRate: Double
    let videoBitrate: Int
    let videoCodec: AVVideoCodecType
    let fileType: AVFileType
    let profileLevel: String
    let includeAudio: Bool
    let audioSampleRate: Int
    let audioChannels: Int
    let audioBitrate: Int
    let transform: CGAffineTransform
    
    static let presets: [ExportPreset] = [
        ExportPreset(
            name: "4K - High Quality",
            settings: ExportSettings(
                resolution: CGSize(width: 3840, height: 2160),
                frameRate: 30.0,
                videoBitrate: 50_000_000,
                videoCodec: .hevc,
                fileType: .mov,
                profileLevel: AVVideoProfileLevelH264HighAutoLevel,
                includeAudio: true,
                audioSampleRate: 48000,
                audioChannels: 2,
                audioBitrate: 320_000,
                transform: .identity
            )
        ),
        ExportPreset(
            name: "1080p - High Quality",
            settings: ExportSettings(
                resolution: CGSize(width: 1920, height: 1080),
                frameRate: 30.0,
                videoBitrate: 20_000_000,
                videoCodec: .h264,
                fileType: .mov,
                profileLevel: AVVideoProfileLevelH264HighAutoLevel,
                includeAudio: true,
                audioSampleRate: 48000,
                audioChannels: 2,
                audioBitrate: 256_000,
                transform: .identity
            )
        ),
        ExportPreset(
            name: "720p - Medium Quality",
            settings: ExportSettings(
                resolution: CGSize(width: 1280, height: 720),
                frameRate: 30.0,
                videoBitrate: 8_000_000,
                videoCodec: .h264,
                fileType: .mov,
                profileLevel: AVVideoProfileLevelH264MainAutoLevel,
                includeAudio: true,
                audioSampleRate: 44100,
                audioChannels: 2,
                audioBitrate: 128_000,
                transform: .identity
            )
        ),
        ExportPreset(
            name: "480p - Compact",
            settings: ExportSettings(
                resolution: CGSize(width: 854, height: 480),
                frameRate: 30.0,
                videoBitrate: 2_500_000,
                videoCodec: .h264,
                fileType: .mov,
                profileLevel: AVVideoProfileLevelH264BaselineAutoLevel,
                includeAudio: true,
                audioSampleRate: 44100,
                audioChannels: 2,
                audioBitrate: 96_000,
                transform: .identity
            )
        )
    ]
}

struct ExportPreset: Identifiable {
    let id = UUID()
    let name: String
    let settings: ExportSettings
}

enum ExportError: LocalizedError {
    case noOriginalAsset
    case failedToCreateAssetWriter
    case failedToCreateVideoInput
    case cannotAddVideoInput
    case assetWriterNotConfigured
    case failedToStartWriting
    case failedToCreatePixelBuffer
    case failedToAppendPixelBuffer
    case failedToAppendAudioBuffer
    case missingFrameData
    case exportCancelled
    case unknownExportError
    
    var errorDescription: String? {
        switch self {
        case .noOriginalAsset:
            return "No original video asset available"
        case .failedToCreateAssetWriter:
            return "Failed to create video writer"
        case .failedToCreateVideoInput:
            return "Failed to create video input"
        case .cannotAddVideoInput:
            return "Cannot add video input to writer"
        case .assetWriterNotConfigured:
            return "Video writer not properly configured"
        case .failedToStartWriting:
            return "Failed to start video writing"
        case .failedToCreatePixelBuffer:
            return "Failed to create pixel buffer for frame"
        case .failedToAppendPixelBuffer:
            return "Failed to append video frame"
        case .failedToAppendAudioBuffer:
            return "Failed to append audio data"
        case .missingFrameData:
            return "Frame data is missing or corrupted"
        case .exportCancelled:
            return "Export was cancelled"
        case .unknownExportError:
            return "An unknown error occurred during export"
        }
    }
}