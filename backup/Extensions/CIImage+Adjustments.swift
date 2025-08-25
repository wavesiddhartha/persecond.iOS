import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension CIImage {
    
    func applyingAdjustmentSet(_ adjustments: AdjustmentSet) -> CIImage {
        var currentImage = self
        
        // Apply exposure adjustment
        if adjustments.exposure != 0.0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = currentImage
            filter.ev = Float(adjustments.exposure)
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        // Apply highlight and shadow adjustments
        if adjustments.highlights != 0.0 || adjustments.shadows != 0.0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = currentImage
            filter.highlightAmount = Float(adjustments.highlights / 100.0)
            filter.shadowAmount = Float(adjustments.shadows / 100.0)
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        // Apply color controls (contrast, brightness, saturation)
        if adjustments.contrast != 0.0 || adjustments.brightness != 0.0 || adjustments.saturation != 0.0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = currentImage
            filter.contrast = Float(1.0 + adjustments.contrast / 100.0)
            filter.brightness = Float(adjustments.brightness / 100.0)
            filter.saturation = Float(1.0 + adjustments.saturation / 100.0)
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        // Apply temperature and tint
        if adjustments.temperature != 0.0 || adjustments.tint != 0.0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = currentImage
            
            // Convert temperature adjustment to kelvin values
            let neutralTemp: Float = 6500
            let tempAdjust = Float(adjustments.temperature * 100)
            filter.neutral = CIVector(x: CGFloat(neutralTemp + tempAdjust), y: CGFloat(adjustments.tint))
            filter.targetNeutral = CIVector(x: CGFloat(neutralTemp), y: 0)
            
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        // Apply hue adjustment
        if adjustments.hue != 0.0 {
            let filter = CIFilter.hueAdjust()
            filter.inputImage = currentImage
            filter.angle = Float(adjustments.hue * .pi / 180.0)
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        // Apply vibrancy
        if adjustments.vibrancy != 0.0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = currentImage
            filter.amount = Float(adjustments.vibrancy / 100.0)
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        // Apply sharpness and definition
        if adjustments.sharpness != 0.0 || adjustments.definition != 0.0 {
            let filter = CIFilter.unsharpMask()
            filter.inputImage = currentImage
            filter.intensity = Float(adjustments.sharpness / 100.0)
            filter.radius = Float(max(0.5, adjustments.definition / 10.0))
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        // Apply noise reduction
        if adjustments.noiseReduction > 0.0 {
            let filter = CIFilter.noiseReduction()
            filter.inputImage = currentImage
            filter.noiseLevel = Float(adjustments.noiseReduction / 100.0)
            filter.sharpness = 0.4
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        // Apply vignette
        if adjustments.vignette != 0.0 {
            let filter = CIFilter.vignette()
            filter.inputImage = currentImage
            filter.intensity = Float(adjustments.vignette / 100.0)
            filter.radius = 1.0
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        // Apply grain
        if adjustments.grain > 0.0 {
            currentImage = currentImage.applyingGrain(amount: adjustments.grain)
        }
        
        return currentImage
    }
    
    private func applyingGrain(amount: Double) -> CIImage {
        guard amount > 0.0 else { return self }
        
        // Create random noise
        let randomFilter = CIFilter.randomGenerator()
        guard let randomImage = randomFilter.outputImage else { return self }
        
        // Convert to monochrome grain
        let grainImage = randomImage
            .cropped(to: extent)
            .applyingFilter("CIColorMonochrome", parameters: [
                kCIInputColorKey: CIColor.white,
                kCIInputIntensityKey: 1.0
            ])
        
        // Blend with overlay mode
        let blendFilter = CIFilter.overlayBlendMode()
        blendFilter.inputImage = self
        blendFilter.backgroundImage = grainImage
        
        guard let blendedImage = blendFilter.outputImage else { return self }
        
        // Mix back with original based on grain amount
        let mixFilter = CIFilter.blendWithMask()
        mixFilter.inputImage = blendedImage
        mixFilter.backgroundImage = self
        
        let maskImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: amount / 100.0))
            .cropped(to: extent)
        mixFilter.maskImage = maskImage
        
        return mixFilter.outputImage ?? self
    }
    
    // Convenience method for creating images from colors  
    static func image(color: CIColor, extent: CGRect) -> CIImage {
        let filter = CIFilter.constantColorGenerator()
        filter.color = color
        return filter.outputImage?.cropped(to: extent) ?? CIImage()
    }
    
    // Method to get the dominant colors in the image
    func dominantColors(count: Int = 5) -> [CIColor] {
        let filter = CIFilter.areaAverage()
        filter.inputImage = self
        filter.extent = extent
        
        guard let outputImage = filter.outputImage else { return [] }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        
        context.render(outputImage,
                      toBitmap: &bitmap,
                      rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8,
                      colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        
        let red = Double(bitmap[0]) / 255.0
        let green = Double(bitmap[1]) / 255.0
        let blue = Double(bitmap[2]) / 255.0
        let alpha = Double(bitmap[3]) / 255.0
        
        return [CIColor(red: red, green: green, blue: blue, alpha: alpha)]
    }
    
    // Method to calculate image histogram
    func histogram() -> (red: [Int], green: [Int], blue: [Int]) {
        let filter = CIFilter.areaHistogram()
        filter.inputImage = self
        filter.extent = extent
        filter.scale = 1.0
        filter.count = 256
        
        guard let outputImage = filter.outputImage else {
            return (red: Array(repeating: 0, count: 256),
                    green: Array(repeating: 0, count: 256),
                    blue: Array(repeating: 0, count: 256))
        }
        
        var histogramData = [Float](repeating: 0, count: 256 * 4)
        let context = CIContext()
        
        context.render(outputImage,
                      toBitmap: &histogramData,
                      rowBytes: 256 * 4 * MemoryLayout<Float>.size,
                      bounds: outputImage.extent,
                      format: .RGBAf,
                      colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        
        var red = [Int](repeating: 0, count: 256)
        var green = [Int](repeating: 0, count: 256)
        var blue = [Int](repeating: 0, count: 256)
        
        for i in 0..<256 {
            red[i] = Int(histogramData[i * 4] * 255)
            green[i] = Int(histogramData[i * 4 + 1] * 255)
            blue[i] = Int(histogramData[i * 4 + 2] * 255)
        }
        
        return (red: red, green: green, blue: blue)
    }
    
    // Method to detect if image is overexposed or underexposed
    func exposureAnalysis() -> (overexposed: Double, underexposed: Double) {
        let histogram = self.histogram()
        let totalPixels = Double(histogram.red.reduce(0, +))
        
        // Count pixels in extreme ranges
        let underexposedCount = Double(histogram.red[0..<16].reduce(0, +))
        let overexposedCount = Double(histogram.red[240..<256].reduce(0, +))
        
        let underexposedPercentage = totalPixels > 0 ? underexposedCount / totalPixels : 0
        let overexposedPercentage = totalPixels > 0 ? overexposedCount / totalPixels : 0
        
        return (overexposed: overexposedPercentage, underexposed: underexposedPercentage)
    }
}