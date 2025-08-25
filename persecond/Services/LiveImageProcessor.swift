import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Combine
import Metal

class LiveImageProcessor: ObservableObject {
    
    private let ciContext: CIContext
    private var filterChain: [CIFilter] = []
    private var cachedBaseImage: CIImage?
    private var isProcessing = false
    
    @Published var processedImage: CIImage?
    @Published var processingError: Error?
    
    private let processingQueue = DispatchQueue(label: "image.processing.queue", qos: .userInteractive)
    private var cancellables = Set<AnyCancellable>()
    
    init(metalDevice: MTLDevice) {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .useSoftwareRenderer: false,
            .highQualityDownsample: true,
            .cacheIntermediates: false,
            .allowLowPower: false // Force high performance GPU
        ]
        
        self.ciContext = CIContext(mtlDevice: metalDevice, options: options)
        setupFilterChain()
    }
    
    private func setupFilterChain() {
        filterChain = [
            CIFilter.exposureAdjust(),
            CIFilter.highlightShadowAdjust(),
            CIFilter.colorControls(),
            CIFilter.temperatureAndTint(),
            CIFilter.hueAdjust(),
            CIFilter.vibrance(),
            CIFilter.unsharpMask(),
            CIFilter.noiseReduction(),
            CIFilter.vignette()
        ]
    }
    
    func setBaseImage(_ image: CIImage) {
        cachedBaseImage = image
    }
    
    func processImageLive(_ adjustments: AdjustmentSet) {
        guard let baseImage = cachedBaseImage else { return }
        
        guard !isProcessing else { return }
        isProcessing = true
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let processedImage = self.applyAdjustments(to: baseImage, adjustments: adjustments)
                
                DispatchQueue.main.async {
                    self.processedImage = processedImage
                    self.processingError = nil
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.processingError = error
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func applyAdjustments(to image: CIImage, adjustments: AdjustmentSet) -> CIImage {
        var currentImage = image
        
        if adjustments.exposure != 0.0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = currentImage
            filter.ev = Float(adjustments.exposure)
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        if adjustments.highlights != 0.0 || adjustments.shadows != 0.0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = currentImage
            filter.highlightAmount = Float(adjustments.highlights / 100.0)
            filter.shadowAmount = Float(adjustments.shadows / 100.0)
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        if adjustments.contrast != 0.0 || adjustments.brightness != 0.0 || 
           adjustments.saturation != 0.0 || adjustments.blackPoint != 0.0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = currentImage
            filter.contrast = Float(1.0 + adjustments.contrast / 100.0)
            filter.brightness = Float(adjustments.brightness / 100.0)
            filter.saturation = Float(1.0 + adjustments.saturation / 100.0)
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        if adjustments.temperature != 0.0 || adjustments.tint != 0.0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = currentImage
            
            let neutralTemp: Float = 6500
            let tempAdjust = Float(adjustments.temperature * 100)
            filter.neutral = CIVector(x: CGFloat(neutralTemp + tempAdjust), y: CGFloat(adjustments.tint))
            filter.targetNeutral = CIVector(x: CGFloat(neutralTemp), y: 0)
            
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        if adjustments.hue != 0.0 {
            let filter = CIFilter.hueAdjust()
            filter.inputImage = currentImage
            filter.angle = Float(adjustments.hue * .pi / 180.0)
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        if adjustments.vibrancy != 0.0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = currentImage
            filter.amount = Float(adjustments.vibrancy / 100.0)
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        if adjustments.sharpness != 0.0 || adjustments.definition != 0.0 {
            let filter = CIFilter.unsharpMask()
            filter.inputImage = currentImage
            filter.intensity = Float(adjustments.sharpness / 100.0)
            filter.radius = Float(max(0.5, adjustments.definition / 10.0))
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        if adjustments.noiseReduction > 0.0 {
            let filter = CIFilter.noiseReduction()
            filter.inputImage = currentImage
            filter.noiseLevel = Float(adjustments.noiseReduction / 100.0)
            filter.sharpness = 0.4
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        if adjustments.vignette != 0.0 {
            let filter = CIFilter.vignette()
            filter.inputImage = currentImage
            filter.intensity = Float(adjustments.vignette / 100.0)
            filter.radius = 1.0
            if let output = filter.outputImage {
                currentImage = output
            }
        }
        
        if adjustments.grain > 0.0 {
            currentImage = applyGrain(to: currentImage, amount: adjustments.grain)
        }
        
        return currentImage
    }
    
    private func applyGrain(to image: CIImage, amount: Double) -> CIImage {
        let randomFilter = CIFilter.randomGenerator()
        guard let randomImage = randomFilter.outputImage else { return image }
        
        let grainImage = randomImage
            .cropped(to: image.extent)
            .applyingFilter("CIColorMonochrome", parameters: [
                kCIInputColorKey: CIColor.white,
                kCIInputIntensityKey: 1.0
            ])
        
        let blendFilter = CIFilter.overlayBlendMode()
        blendFilter.inputImage = image
        blendFilter.backgroundImage = grainImage
        
        guard let blendedImage = blendFilter.outputImage else { return image }
        
        let mixFilter = CIFilter.blendWithMask()
        mixFilter.inputImage = blendedImage
        mixFilter.backgroundImage = image
        
        let maskImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: amount / 100.0))
            .cropped(to: image.extent)
        mixFilter.maskImage = maskImage
        
        return mixFilter.outputImage ?? image
    }
    
    func processImageSync(_ image: CIImage, adjustments: AdjustmentSet) -> CIImage {
        return applyAdjustments(to: image, adjustments: adjustments)
    }
    
    func renderToCGImage(_ ciImage: CIImage, size: CGSize) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        return ciContext.createCGImage(ciImage, from: rect)
    }
    
    func renderToUIImage(_ ciImage: CIImage, size: CGSize) -> UIImage? {
        guard let cgImage = renderToCGImage(ciImage, size: size) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    func createPreset(name: String, adjustments: AdjustmentSet) -> ImagePreset {
        return ImagePreset(name: name, adjustments: adjustments)
    }
    
    func applyPreset(_ preset: ImagePreset, to image: CIImage) -> CIImage {
        return applyAdjustments(to: image, adjustments: preset.adjustments)
    }
    
    func generateAutoAdjustments(for image: CIImage) -> AdjustmentSet {
        let adjustments = AdjustmentSet()
        
        let features = image.autoAdjustmentFilters()
        
        for filter in features {
            if let exposureFilter = filter as? CIFilter,
               exposureFilter.name == "CIExposureAdjust" {
                if let ev = exposureFilter.value(forKey: "inputEV") as? NSNumber {
                    adjustments.exposure = ev.doubleValue * 100.0
                }
            }
        }
        
        return adjustments
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }
}

struct ImagePreset: Codable, Identifiable {
    let id = UUID()
    let name: String
    let adjustments: AdjustmentSet
    let createdDate: Date = Date()
}

extension CIImage {
    var uiImage: UIImage? {
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(self, from: self.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}