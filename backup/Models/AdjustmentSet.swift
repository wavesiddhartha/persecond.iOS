import Foundation
import Combine

class AdjustmentSet: ObservableObject, Codable {
    
    @Published var exposure: Double = 0.0
    @Published var highlights: Double = 0.0
    @Published var shadows: Double = 0.0
    @Published var contrast: Double = 0.0
    @Published var brightness: Double = 0.0
    @Published var blackPoint: Double = 0.0
    @Published var saturation: Double = 0.0
    @Published var vibrancy: Double = 0.0
    @Published var temperature: Double = 0.0
    @Published var tint: Double = 0.0
    @Published var hue: Double = 0.0
    @Published var sharpness: Double = 0.0
    @Published var definition: Double = 0.0
    @Published var noiseReduction: Double = 0.0
    @Published var vignette: Double = 0.0
    @Published var grain: Double = 0.0
    
    init() {}
    
    enum CodingKeys: CodingKey {
        case exposure, highlights, shadows, contrast, brightness, blackPoint
        case saturation, vibrancy, temperature, tint, hue, sharpness
        case definition, noiseReduction, vignette, grain
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        exposure = try container.decode(Double.self, forKey: .exposure)
        highlights = try container.decode(Double.self, forKey: .highlights)
        shadows = try container.decode(Double.self, forKey: .shadows)
        contrast = try container.decode(Double.self, forKey: .contrast)
        brightness = try container.decode(Double.self, forKey: .brightness)
        blackPoint = try container.decode(Double.self, forKey: .blackPoint)
        saturation = try container.decode(Double.self, forKey: .saturation)
        vibrancy = try container.decode(Double.self, forKey: .vibrancy)
        temperature = try container.decode(Double.self, forKey: .temperature)
        tint = try container.decode(Double.self, forKey: .tint)
        hue = try container.decode(Double.self, forKey: .hue)
        sharpness = try container.decode(Double.self, forKey: .sharpness)
        definition = try container.decode(Double.self, forKey: .definition)
        noiseReduction = try container.decode(Double.self, forKey: .noiseReduction)
        vignette = try container.decode(Double.self, forKey: .vignette)
        grain = try container.decode(Double.self, forKey: .grain)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(exposure, forKey: .exposure)
        try container.encode(highlights, forKey: .highlights)
        try container.encode(shadows, forKey: .shadows)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(blackPoint, forKey: .blackPoint)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(vibrancy, forKey: .vibrancy)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(tint, forKey: .tint)
        try container.encode(hue, forKey: .hue)
        try container.encode(sharpness, forKey: .sharpness)
        try container.encode(definition, forKey: .definition)
        try container.encode(noiseReduction, forKey: .noiseReduction)
        try container.encode(vignette, forKey: .vignette)
        try container.encode(grain, forKey: .grain)
    }
    
    func reset() {
        exposure = 0.0
        highlights = 0.0
        shadows = 0.0
        contrast = 0.0
        brightness = 0.0
        blackPoint = 0.0
        saturation = 0.0
        vibrancy = 0.0
        temperature = 0.0
        tint = 0.0
        hue = 0.0
        sharpness = 0.0
        definition = 0.0
        noiseReduction = 0.0
        vignette = 0.0
        grain = 0.0
    }
    
    func copy() -> AdjustmentSet {
        let copy = AdjustmentSet()
        copy.exposure = exposure
        copy.highlights = highlights
        copy.shadows = shadows
        copy.contrast = contrast
        copy.brightness = brightness
        copy.blackPoint = blackPoint
        copy.saturation = saturation
        copy.vibrancy = vibrancy
        copy.temperature = temperature
        copy.tint = tint
        copy.hue = hue
        copy.sharpness = sharpness
        copy.definition = definition
        copy.noiseReduction = noiseReduction
        copy.vignette = vignette
        copy.grain = grain
        return copy
    }
}