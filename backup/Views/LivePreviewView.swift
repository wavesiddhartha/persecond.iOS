import SwiftUI
import CoreImage
import MetalKit

struct LivePreviewView: View {
    @ObservedObject var project: VideoProject
    @ObservedObject var renderer: MetalRenderer
    @ObservedObject var imageProcessor: LiveImageProcessor
    
    @State private var showOriginal: Bool = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var showingComparisonMode: Bool = false
    @State private var comparisonSplitPosition: CGFloat = 0.5
    @State private var autoHideOverlay: Bool = false
    
    private let maxZoom: CGFloat = 8.0
    private let minZoom: CGFloat = 0.5
    
    var currentFrame: FrameAdjustment? {
        project.currentFrame
    }
    
    var currentImage: CIImage? {
        guard let frame = currentFrame,
              let uiImage = frame.thumbnail else { return nil }
        
        return CIImage(image: uiImage)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geometry in
                ZStack {
                    if let image = currentImage {
                        if showingComparisonMode {
                            comparisonView(image: image, geometry: geometry)
                        } else {
                            singleImageView(image: image, geometry: geometry)
                        }
                    } else {
                        placeholderView
                    }
                    
                    if !autoHideOverlay {
                        LivePreviewOverlay(
                            showOriginal: $showOriginal,
                            zoomScale: $zoomScale,
                            frameNumber: project.currentFrameIndex + 1,
                            totalFrames: project.totalFrames
                        )
                        .allowsHitTesting(false)
                    }
                    
                    if showingComparisonMode {
                        comparisonControls(geometry: geometry)
                    }
                }
                .clipped()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        autoHideOverlay.toggle()
                    }
                }
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newZoom = zoomScale * value
                                zoomScale = max(minZoom, min(maxZoom, newZoom))
                            }
                            .onEnded { _ in
                                if zoomScale < 1.0 {
                                    withAnimation(.spring()) {
                                        zoomScale = 1.0
                                        offset = .zero
                                    }
                                }
                            },
                        
                        DragGesture()
                            .onChanged { value in
                                if zoomScale > 1.0 {
                                    offset = CGSize(
                                        width: offset.width + value.translation.x / 10,
                                        height: offset.height + value.translation.y / 10
                                    )
                                }
                            }
                            .onEnded { _ in
                                if zoomScale <= 1.0 {
                                    withAnimation(.spring()) {
                                        offset = .zero
                                    }
                                }
                            }
                    )
                )
            }
            
            VStack {
                Spacer()
                controlButtons
            }
        }
        .onReceive(project.$currentFrameIndex) { _ in
            imageProcessor.setBaseImage(currentImage)
        }
        .onReceive(project.$globalAdjustments) { adjustments in
            if let image = currentImage {
                imageProcessor.setBaseImage(image)
                imageProcessor.processImageLive(adjustments)
            }
        }
    }
    
    @ViewBuilder
    private func singleImageView(image: CIImage, geometry: GeometryProxy) -> some View {
        MetalPreviewView(
            renderer: renderer,
            imageProcessor: imageProcessor,
            currentImage: .constant(image),
            adjustments: $project.globalAdjustments,
            showOriginal: $showOriginal,
            onTap: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    autoHideOverlay.toggle()
                }
            },
            onLongPress: {
                
            },
            onPinch: { scale in
                
            }
        )
        .scaleEffect(zoomScale)
        .offset(offset)
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    @ViewBuilder
    private func comparisonView(image: CIImage, geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            
            MetalPreviewView(
                renderer: renderer,
                imageProcessor: imageProcessor,
                currentImage: .constant(image),
                adjustments: .constant(AdjustmentSet()),
                showOriginal: .constant(true)
            )
            .frame(width: geometry.size.width * comparisonSplitPosition)
            .clipped()
            
            
            MetalPreviewView(
                renderer: renderer,
                imageProcessor: imageProcessor,
                currentImage: .constant(image),
                adjustments: $project.globalAdjustments,
                showOriginal: .constant(false)
            )
            .frame(width: geometry.size.width * (1.0 - comparisonSplitPosition))
            .clipped()
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let newPosition = value.location.x / geometry.size.width
                    comparisonSplitPosition = max(0.1, min(0.9, newPosition))
                }
        )
    }
    
    @ViewBuilder
    private func comparisonControls(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()
            
            
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: geometry.size.height)
                .offset(x: geometry.size.width * comparisonSplitPosition - geometry.size.width / 2)
                .allowsHitTesting(false)
            
            Spacer()
            
            HStack {
                Text("Original")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                
                Spacer()
                
                Text("Edited")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var placeholderView: some View {
        VStack {
            Image(systemName: "photo")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            Text("No frame selected")
                .font(.headline)
                .foregroundColor(.gray)
        }
    }
    
    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 20) {
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingComparisonMode.toggle()
                }
            }) {
                Image(systemName: showingComparisonMode ? "rectangle.split.2x1" : "rectangle.split.2x1.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.7)))
            }
            
            
            Button(action: resetZoom) {
                Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.7)))
            }
            
            
            Button(action: resetAdjustments) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.7)))
            }
        }
        .padding(.bottom, 20)
    }
    
    private func resetZoom() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            zoomScale = 1.0
            offset = .zero
        }
    }
    
    private func resetAdjustments() {
        withAnimation(.easeInOut(duration: 0.3)) {
            project.globalAdjustments.reset()
        }
    }
}