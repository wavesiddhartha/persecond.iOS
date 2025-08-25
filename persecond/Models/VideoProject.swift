import Foundation
import AVFoundation
import UIKit

class VideoProject: ObservableObject, Codable {
    
    @Published var id = UUID()
    @Published var name: String = ""
    @Published var originalVideoURL: URL?
    @Published var asset: AVAsset?
    @Published var duration: CMTime = .zero
    @Published var frameRate: Float64 = 30.0
    @Published var selectedRange: ClosedRange<Double> = 0.0...1.0
    @Published var frames: [FrameAdjustment] = []
    @Published var currentFrameIndex: Int = 0
    @Published var globalAdjustments: AdjustmentSet = AdjustmentSet()
    @Published var isProcessing: Bool = false
    @Published var exportProgress: Double = 0.0
    @Published var createdDate: Date = Date()
    @Published var lastModifiedDate: Date = Date()
    @Published var isFrameEditingMode: Bool = false
    @Published var markedFrameIndices: Set<Int> = []
    
    var totalFrames: Int {
        frames.count
    }
    
    var selectedFrames: [FrameAdjustment] {
        let startIndex = Int(selectedRange.lowerBound * Double(totalFrames))
        let endIndex = Int(selectedRange.upperBound * Double(totalFrames))
        return Array(frames[startIndex..<min(endIndex, totalFrames)])
    }
    
    var currentFrame: FrameAdjustment? {
        guard currentFrameIndex < frames.count && currentFrameIndex >= 0 else { return nil }
        return frames[currentFrameIndex]
    }
    
    var currentFrameIsMarked: Bool {
        markedFrameIndices.contains(currentFrameIndex)
    }
    
    var markedFrames: [FrameAdjustment] {
        return markedFrameIndices.compactMap { index in
            guard index < frames.count else { return nil }
            return frames[index]
        }
    }
    
    var selectedDuration: CMTime {
        let totalSeconds = duration.seconds
        let selectedSeconds = totalSeconds * (selectedRange.upperBound - selectedRange.lowerBound)
        return CMTime(seconds: selectedSeconds, preferredTimescale: duration.timescale)
    }
    
    init() {}
    
    init(videoURL: URL, asset: AVAsset) {
        self.originalVideoURL = videoURL
        self.asset = asset
        self.duration = asset.duration
        self.name = videoURL.deletingPathExtension().lastPathComponent
        self.frameRate = getFrameRate(from: asset)
    }
    
    enum CodingKeys: CodingKey {
        case id, name, originalVideoURL, durationValue, durationTimescale, frameRate, selectedRange
        case frames, currentFrameIndex, globalAdjustments, createdDate, lastModifiedDate
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        originalVideoURL = try container.decodeIfPresent(URL.self, forKey: .originalVideoURL)
        let durationValue = try container.decode(Int64.self, forKey: .durationValue)
        let durationTimescale = try container.decode(Int32.self, forKey: .durationTimescale)
        duration = CMTime(value: durationValue, timescale: durationTimescale)
        frameRate = try container.decode(Float64.self, forKey: .frameRate)
        selectedRange = try container.decode(ClosedRange<Double>.self, forKey: .selectedRange)
        frames = try container.decode([FrameAdjustment].self, forKey: .frames)
        currentFrameIndex = try container.decode(Int.self, forKey: .currentFrameIndex)
        globalAdjustments = try container.decode(AdjustmentSet.self, forKey: .globalAdjustments)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        lastModifiedDate = try container.decode(Date.self, forKey: .lastModifiedDate)
        
        if let videoURL = originalVideoURL {
            asset = AVAsset(url: videoURL)
        }
        
        isProcessing = false
        exportProgress = 0.0
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(originalVideoURL, forKey: .originalVideoURL)
        try container.encode(duration.value, forKey: .durationValue)
        try container.encode(duration.timescale, forKey: .durationTimescale)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encode(selectedRange, forKey: .selectedRange)
        try container.encode(frames, forKey: .frames)
        try container.encode(currentFrameIndex, forKey: .currentFrameIndex)
        try container.encode(globalAdjustments, forKey: .globalAdjustments)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(lastModifiedDate, forKey: .lastModifiedDate)
    }
    
    private func getFrameRate(from asset: AVAsset) -> Float64 {
        return 30.0 // Default frame rate - will be updated when tracks are loaded
    }
    
    func updateSelectedRange(_ range: ClosedRange<Double>) {
        selectedRange = range
        lastModifiedDate = Date()
    }
    
    func updateCurrentFrame(_ index: Int) {
        guard index >= 0 && index < totalFrames else { return }
        currentFrameIndex = index
        lastModifiedDate = Date()
    }
    
    func nextFrame() {
        guard currentFrameIndex < totalFrames - 1 else { return }
        currentFrameIndex += 1
        lastModifiedDate = Date()
    }
    
    func previousFrame() {
        guard currentFrameIndex > 0 else { return }
        currentFrameIndex -= 1
        lastModifiedDate = Date()
    }
    
    func updateGlobalAdjustments(_ adjustments: AdjustmentSet) {
        globalAdjustments = adjustments.copy()
        lastModifiedDate = Date()
    }
    
    func updateFrameAdjustments(_ adjustments: AdjustmentSet, for frameIndex: Int) {
        guard frameIndex >= 0 && frameIndex < frames.count else { return }
        frames[frameIndex].updateAdjustments(adjustments)
        lastModifiedDate = Date()
    }
    
    func addFrames(_ newFrames: [FrameAdjustment]) {
        frames.append(contentsOf: newFrames)
        lastModifiedDate = Date()
    }
    
    func resetAdjustments() {
        globalAdjustments.reset()
        for i in 0..<frames.count {
            frames[i].adjustments.reset()
            frames[i].isProcessed = false
        }
        lastModifiedDate = Date()
    }
    
    func toggleFrameEditingMode() {
        isFrameEditingMode.toggle()
        lastModifiedDate = Date()
    }
    
    func markCurrentFrame() {
        guard currentFrameIndex < frames.count else { return }
        markedFrameIndices.insert(currentFrameIndex)
        frames[currentFrameIndex].isSelected = true
        lastModifiedDate = Date()
    }
    
    func unmarkCurrentFrame() {
        markedFrameIndices.remove(currentFrameIndex)
        if currentFrameIndex < frames.count {
            frames[currentFrameIndex].isSelected = false
        }
        lastModifiedDate = Date()
    }
    
    func toggleCurrentFrameMark() {
        if currentFrameIsMarked {
            unmarkCurrentFrame()
        } else {
            markCurrentFrame()
        }
    }
    
    func clearAllMarkedFrames() {
        for index in markedFrameIndices {
            if index < frames.count {
                frames[index].isSelected = false
            }
        }
        markedFrameIndices.removeAll()
        lastModifiedDate = Date()
    }
}