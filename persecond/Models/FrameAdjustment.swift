import Foundation
import UIKit
import CoreImage
import AVFoundation

struct FrameAdjustment: Codable, Identifiable, Sendable {
    let id = UUID()
    let frameIndex: Int
    let timestamp: CMTime
    var adjustments: AdjustmentSet
    var thumbnail: UIImage?
    var processedImage: CIImage?
    var isSelected: Bool = false
    var isProcessed: Bool = false
    
    init(frameIndex: Int, timestamp: CMTime, thumbnail: UIImage? = nil) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.thumbnail = thumbnail
        self.adjustments = AdjustmentSet()
    }
    
    enum CodingKeys: CodingKey {
        case frameIndex, timestampValue, timestampTimescale, adjustments, isSelected, isProcessed
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        frameIndex = try container.decode(Int.self, forKey: .frameIndex)
        let timestampValue = try container.decode(Int64.self, forKey: .timestampValue)
        let timestampTimescale = try container.decode(Int32.self, forKey: .timestampTimescale)
        timestamp = CMTime(value: timestampValue, timescale: timestampTimescale)
        adjustments = try container.decode(AdjustmentSet.self, forKey: .adjustments)
        isSelected = try container.decode(Bool.self, forKey: .isSelected)
        isProcessed = try container.decode(Bool.self, forKey: .isProcessed)
        
        thumbnail = nil
        processedImage = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(frameIndex, forKey: .frameIndex)
        try container.encode(timestamp.value, forKey: .timestampValue)
        try container.encode(timestamp.timescale, forKey: .timestampTimescale)
        try container.encode(adjustments, forKey: .adjustments)
        try container.encode(isSelected, forKey: .isSelected)
        try container.encode(isProcessed, forKey: .isProcessed)
    }
    
    mutating func updateAdjustments(_ newAdjustments: AdjustmentSet) {
        adjustments = newAdjustments.copy()
        isProcessed = false
    }
    
    mutating func setProcessedImage(_ image: CIImage) {
        processedImage = image
        isProcessed = true
    }
}