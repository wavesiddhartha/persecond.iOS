import Foundation
import Metal
import MetalKit
import CoreImage
import UIKit
import Combine

class MetalRenderer: NSObject, ObservableObject {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private var currentTexture: MTLTexture?
    
    @Published var isRendering: Bool = false
    @Published var renderingError: Error?
    
    private let renderQueue = DispatchQueue(label: "metal.render.queue", qos: .userInteractive)
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        
        self.commandQueue = commandQueue
        
        let options: [CIContextOption: Any] = [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .useSoftwareRenderer: false
        ]
        
        self.ciContext = CIContext(mtlDevice: device, options: options)
        
        super.init()
    }
    
    func setupMTKView(_ mtkView: MTKView) {
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.framebufferOnly = false
        mtkView.preferredFramesPerSecond = 60
    }
    
    func renderImage(_ ciImage: CIImage, 
                     to drawable: CAMetalDrawable, 
                     colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) {
        
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isRendering = true
                self.renderingError = nil
            }
            
            do {
                let commandBuffer = self.commandQueue.makeCommandBuffer()
                
                let destination = CIRenderDestination(
                    mtlTexture: drawable.texture,
                    commandBuffer: commandBuffer
                )
                destination.colorSpace = colorSpace
                
                _ = try self.ciContext.startTask(toRender: ciImage, to: destination)
                
                commandBuffer?.present(drawable)
                commandBuffer?.commit()
                commandBuffer?.waitUntilCompleted()
                
                DispatchQueue.main.async {
                    self.isRendering = false
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isRendering = false
                    self.renderingError = error
                }
            }
        }
    }
    
    func renderImageSynchronously(_ ciImage: CIImage, 
                                to drawable: CAMetalDrawable) -> Bool {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return false
        }
        
        do {
            let destination = CIRenderDestination(
                mtlTexture: drawable.texture,
                commandBuffer: commandBuffer
            )
            
            _ = try ciContext.startTask(toRender: ciImage, to: destination)
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            return true
        } catch {
            renderingError = error
            return false
        }
    }
    
    func createTexture(from image: UIImage) -> MTLTexture? {
        guard let cgImage = image.cgImage else { return nil }
        
        let textureLoader = MTKTextureLoader(device: device)
        
        do {
            let texture = try textureLoader.newTexture(cgImage: cgImage, options: [
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.shared.rawValue
            ])
            return texture
        } catch {
            print("Failed to create texture: \(error)")
            return nil
        }
    }
    
    func createCIImage(from texture: MTLTexture) -> CIImage {
        return CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ]) ?? CIImage()
    }
    
    func renderToTexture(_ ciImage: CIImage, size: CGSize) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .renderTarget]
        textureDescriptor.storageMode = .shared
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }
        
        do {
            let destination = CIRenderDestination(
                mtlTexture: texture,
                commandBuffer: commandBuffer
            )
            
            _ = try ciContext.startTask(toRender: ciImage, to: destination)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            return texture
        } catch {
            print("Failed to render to texture: \(error)")
            return nil
        }
    }
    
    func copyTexture(_ sourceTexture: MTLTexture) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = sourceTexture.textureType
        textureDescriptor.pixelFormat = sourceTexture.pixelFormat
        textureDescriptor.width = sourceTexture.width
        textureDescriptor.height = sourceTexture.height
        textureDescriptor.depth = sourceTexture.depth
        textureDescriptor.mipmapLevelCount = sourceTexture.mipmapLevelCount
        textureDescriptor.arrayLength = sourceTexture.arrayLength
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.storageMode = .shared
        
        guard let destinationTexture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return nil
        }
        
        blitEncoder.copy(from: sourceTexture,
                        sourceSlice: 0,
                        sourceLevel: 0,
                        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                        sourceSize: MTLSize(width: sourceTexture.width, height: sourceTexture.height, depth: sourceTexture.depth),
                        to: destinationTexture,
                        destinationSlice: 0,
                        destinationLevel: 0,
                        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return destinationTexture
    }
    
    func optimizeForLivePreview() {
        commandQueue.maxCommandBufferCount = 3
    }
    
    func clearCachedTextures() {
        currentTexture = nil
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
        clearCachedTextures()
    }
}