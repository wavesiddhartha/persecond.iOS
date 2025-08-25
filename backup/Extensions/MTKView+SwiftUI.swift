import SwiftUI
import MetalKit
import CoreImage

struct MetalPreviewView: UIViewRepresentable {
    @ObservedObject var renderer: MetalRenderer
    @ObservedObject var imageProcessor: LiveImageProcessor
    @Binding var currentImage: CIImage?
    @Binding var adjustments: AdjustmentSet
    @Binding var showOriginal: Bool
    
    let onTap: (() -> Void)?
    let onLongPress: (() -> Void)?
    let onPinch: ((CGFloat) -> Void)?
    
    init(renderer: MetalRenderer,
         imageProcessor: LiveImageProcessor,
         currentImage: Binding<CIImage?>,
         adjustments: Binding<AdjustmentSet>,
         showOriginal: Binding<Bool> = .constant(false),
         onTap: (() -> Void)? = nil,
         onLongPress: (() -> Void)? = nil,
         onPinch: ((CGFloat) -> Void)? = nil) {
        
        self.renderer = renderer
        self.imageProcessor = imageProcessor
        self._currentImage = currentImage
        self._adjustments = adjustments
        self._showOriginal = showOriginal
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.onPinch = onPinch
    }
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        renderer.setupMTKView(mtkView)
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        mtkView.addGestureRecognizer(tapGesture)
        
        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress)
        )
        mtkView.addGestureRecognizer(longPressGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch)
        )
        mtkView.addGestureRecognizer(pinchGesture)
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateImage()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        let parent: MetalPreviewView
        private var displayLink: CADisplayLink?
        private var lastAdjustments = AdjustmentSet()
        
        init(_ parent: MetalPreviewView) {
            self.parent = parent
            super.init()
            setupDisplayLink()
        }
        
        private func setupDisplayLink() {
            displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
            displayLink?.preferredFramesPerSecond = 60
            displayLink?.add(to: .current, forMode: .common)
        }
        
        @objc private func displayLinkDidFire() {
            updateImage()
        }
        
        func updateImage() {
            guard let currentImage = parent.currentImage else { return }
            
            let adjustmentsChanged = !areAdjustmentsEqual(lastAdjustments, parent.adjustments)
            
            if adjustmentsChanged {
                lastAdjustments = parent.adjustments.copy()
                
                let imageToRender = parent.showOriginal ? currentImage : 
                    parent.imageProcessor.processImageSync(currentImage, adjustments: parent.adjustments)
                
                DispatchQueue.main.async {
                    // Trigger view update
                }
            }
        }
        
        private func areAdjustmentsEqual(_ lhs: AdjustmentSet, _ rhs: AdjustmentSet) -> Bool {
            return lhs.exposure == rhs.exposure &&
                   lhs.highlights == rhs.highlights &&
                   lhs.shadows == rhs.shadows &&
                   lhs.contrast == rhs.contrast &&
                   lhs.brightness == rhs.brightness &&
                   lhs.blackPoint == rhs.blackPoint &&
                   lhs.saturation == rhs.saturation &&
                   lhs.vibrancy == rhs.vibrancy &&
                   lhs.temperature == rhs.temperature &&
                   lhs.tint == rhs.tint &&
                   lhs.hue == rhs.hue &&
                   lhs.sharpness == rhs.sharpness &&
                   lhs.definition == rhs.definition &&
                   lhs.noiseReduction == rhs.noiseReduction &&
                   lhs.vignette == rhs.vignette &&
                   lhs.grain == rhs.grain
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            
        }
        
        func draw(in view: MTKView) {
            guard let currentImage = parent.currentImage,
                  let drawable = view.currentDrawable else { return }
            
            let imageToRender = parent.showOriginal ? currentImage : 
                parent.imageProcessor.processImageSync(currentImage, adjustments: parent.adjustments)
            
            parent.renderer.renderImage(imageToRender, to: drawable)
        }
        
        @objc func handleTap() {
            parent.onTap?()
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                parent.showOriginal = true
                parent.onLongPress?()
            case .ended, .cancelled:
                parent.showOriginal = false
            default:
                break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            parent.onPinch?(gesture.scale)
        }
        
        deinit {
            displayLink?.invalidate()
        }
    }
}

struct LivePreviewOverlay: View {
    @Binding var showOriginal: Bool
    @Binding var zoomScale: CGFloat
    let frameNumber: Int
    let totalFrames: Int
    
    var body: some View {
        VStack {
            HStack {
                if showOriginal {
                    Text("Original")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .animation(.easeInOut(duration: 0.2), value: showOriginal)
                }
                
                Spacer()
                
                Text("Frame \(frameNumber)/\(totalFrames)")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            .padding()
            
            Spacer()
            
            if zoomScale > 1.0 {
                HStack {
                    Spacer()
                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.trailing)
                        .padding(.bottom)
                }
            }
        }
    }
}