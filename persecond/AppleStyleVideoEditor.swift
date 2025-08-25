import SwiftUI
import MetalKit
import UIKit

struct AppleStyleVideoEditor: View {
    @ObservedObject var project: VideoProject
    @StateObject private var metalRenderer = MetalRenderer()
    @StateObject private var imageProcessor: LiveImageProcessor
    
    @State private var selectedAdjustmentCategory: AdjustmentCategory = .adjust
    @State private var showingExportView = false
    @State private var isShowingAdjustments = false
    @State private var selectedControl: AdjustmentControl?
    @State private var isDraggingSlider = false
    
    // Video zoom and pan functionality
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    
    // Undo/Redo functionality
    @State private var undoStack: [AdjustmentSet] = []
    @State private var redoStack: [AdjustmentSet] = []
    
    
    init(project: VideoProject) {
        self.project = project
        // Safely initialize Metal device with fallback
        let metalDevice = MTLCreateSystemDefaultDevice() ?? {
            fatalError("Metal is not supported on this device")
        }()
        self._imageProcessor = StateObject(wrappedValue: LiveImageProcessor(metalDevice: metalDevice))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full white background covering everything
                Color.white
                    .ignoresSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Top navigation bar
                    topNavigationBar
                    
                    // Main video preview area
                    videoPreviewArea
                        .frame(maxHeight: .infinity)
                    
                    // Bottom adjustment controls with premium transitions
                    if isShowingAdjustments {
                        adjustmentControlsArea
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                                removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 1.05))
                            ))
                    } else {
                        VStack(spacing: 0) {
                            frameTimelineView
                            bottomToolbar
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                            removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 1.05))
                        ))
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .background(Color.white.ignoresSafeArea(.all))
        .sheet(isPresented: $showingExportView) {
            ExportView(project: project)
        }
        .onAppear {
            // Initialize live preview when view appears
            updateLivePreview()
        }
        .onChange(of: project.currentFrameIndex) { _ in
            // Update preview when frame changes
            updateLivePreview()
        }
        // Enhanced performance monitoring
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Optimize performance when app becomes active
            metalRenderer.optimizeForLivePreview()
        }
    }
    
    @ViewBuilder
    private var topNavigationBar: some View {
        HStack {
            // Back button
            Button("Back") {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                // Reset project and go back to import screen
                project.frames.removeAll()
                project.currentFrameIndex = 0
                project.globalAdjustments.reset()
                project.markedFrameIndices.removeAll()
                project.originalVideoURL = nil
                project.asset = nil
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.black)
            .cornerRadius(20)
            
            // Undo/Redo buttons
            HStack(spacing: 8) {
                Button(action: {
                    undoLastChange()
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(undoStack.isEmpty ? .gray : .blue)
                        .clipShape(Circle())
                }
                .disabled(undoStack.isEmpty)
                
                Button(action: {
                    redoLastChange()
                }) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(redoStack.isEmpty ? .gray : .blue)
                        .clipShape(Circle())
                }
                .disabled(redoStack.isEmpty)
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                // Premium persecond logo with gradient
                HStack(spacing: 0.5) {
                    Text("per")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(
                            colors: [.black, .gray],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Text("second")
                        .font(.system(size: 12, weight: .ultraLight, design: .rounded))
                        .foregroundColor(.black.opacity(0.7))
                        .offset(y: 2)
                }
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                // Premium mode indicator with glow effect
                HStack(spacing: 6) {
                    Circle()
                        .fill(project.currentFrameIsMarked ? 
                            LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [.gray, .black.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 8, height: 8)
                        .shadow(color: project.currentFrameIsMarked ? .orange.opacity(0.6) : .clear, radius: 4)
                    
                    Text(project.currentFrameIsMarked ? "FRAME" : "GLOBAL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(project.currentFrameIsMarked ? .orange : .gray)
                        .tracking(0.5)
                }
            }
            
            Spacer()
            
            Button("Export") {
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()
                
                print("🎬 EXPORT BUTTON TAPPED!")
                print("📊 Project has \(project.totalFrames) frames")
                
                // Reset all states and show export
                isShowingAdjustments = false
                selectedControl = nil
                
                // Ensure we have a valid project before showing export
                guard project.totalFrames > 0 else { 
                    print("❌ No frames to export!")
                    return 
                }
                
                print("✅ Opening export view...")
                showingExportView = true
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.green)
            .cornerRadius(25)
            .shadow(color: .green.opacity(0.4), radius: 6, x: 0, y: 3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.white)
    }
    
    @ViewBuilder
    private var videoPreviewArea: some View {
        ZStack {
            if let currentFrame = project.currentFrame,
               let thumbnail = currentFrame.thumbnail,
               let ciImage = CIImage(image: thumbnail) {
                
                // Metal-accelerated live preview with frame-specific or global adjustments
                let adjustmentsToShow = project.currentFrameIsMarked ? 
                    currentFrame.adjustments : project.globalAdjustments
                
                GeometryReader { geometry in
                    ZStack {
                        // Zoomable and pannable video view
                        MetalPreviewView(
                            ciImage: ciImage,
                            adjustments: adjustmentsToShow,
                            metalRenderer: metalRenderer,
                            imageProcessor: imageProcessor
                        )
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height,
                            alignment: .center
                        )
                        .clipped()
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoomScale = max(0.5, min(value, 3.0))
                                }
                                .onEnded { value in
                                    zoomScale = max(0.5, min(value, 3.0))
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newOffset = CGSize(
                                        width: lastPanOffset.width + value.translation.width,
                                        height: lastPanOffset.height + value.translation.height
                                    )
                                    panOffset = newOffset
                                }
                                .onEnded { value in
                                    lastPanOffset = panOffset
                                }
                        )
                        
                        // Zoom controls overlay
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                
                                VStack(spacing: 8) {
                                    // Reset zoom button
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            zoomScale = 1.0
                                            panOffset = .zero
                                            lastPanOffset = .zero
                                        }
                                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                        impactFeedback.impactOccurred()
                                    }) {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(10)
                                            .background(.black.opacity(0.7))
                                            .clipShape(Circle())
                                    }
                                    
                                    // Zoom level indicator
                                    Text("\(Int(zoomScale * 100))%")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.7))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 16)
                        }
                    }
                }
                
            } else {
                // Placeholder when no frame is selected - properly centered
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "video")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                Text("No video loaded")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height,
                                alignment: .center
                            )
                        )
                }
            }
        }
        .background(.white)
        .onTapGesture(count: 2) {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
            project.toggleCurrentFrameMark()
        }
        .onTapGesture(count: 1) {
            // Only toggle adjustments if we're not zoomed in
            if zoomScale <= 1.1 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isShowingAdjustments.toggle()
                }
            }
        }
    }
    
    @ViewBuilder
    private var frameTimelineView: some View {
        VStack(spacing: 8) {
            // Frame counter with mark status and navigation
            VStack(spacing: 8) {
                HStack {
                    Text("Frame")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        VStack(spacing: 2) {
                            Text("\(project.currentFrameIndex + 1) of \(project.totalFrames)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.white)
                            
                            // Performance indicator (frame rate)
                            if project.frameRate > 0 {
                                Text("\(String(format: "%.0f", project.frameRate))fps")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                        }
                        
                        if project.currentFrameIsMarked {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    Spacer()
                    
                    // Mark/Unmark Frame button
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        project.toggleCurrentFrameMark()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: project.currentFrameIsMarked ? "pin.slash" : "pin")
                            Text(project.currentFrameIsMarked ? "Unmark" : "Mark")
                        }
                        .font(.caption)
                        .foregroundColor(project.currentFrameIsMarked ? .red : .yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(project.currentFrameIsMarked ? .red.opacity(0.2) : .yellow.opacity(0.2))
                        .cornerRadius(6)
                    }
                }
                
                // Marked frame navigation - only show if there are marked frames
                if !project.markedFrameIndices.isEmpty {
                    HStack(spacing: 12) {
                        Text("\(project.markedFrameIndices.count) marked frame\(project.markedFrameIndices.count == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            // Previous marked frame
                            Button(action: {
                                goToPreviousMarkedFrame()
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.orange)
                                    .cornerRadius(6)
                            }
                            .disabled(!hasPreviousMarkedFrame())
                            .opacity(hasPreviousMarkedFrame() ? 1.0 : 0.5)
                            
                            Text("Navigate")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.black)
                            
                            // Next marked frame
                            Button(action: {
                                goToNextMarkedFrame()
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.orange)
                                    .cornerRadius(6)
                            }
                            .disabled(!hasNextMarkedFrame())
                            .opacity(hasNextMarkedFrame() ? 1.0 : 0.5)
                        }
                        
                        Spacer()
                        
                        // Batch operations for marked frames
                        Menu {
                            Button("Apply Current Adjustments to All Marked", action: {
                                applyCurrentAdjustmentsToMarkedFrames()
                            })
                            
                            Button("Reset All Marked Frames", action: {
                                resetAllMarkedFrames()
                            })
                            
                            Button("Copy Adjustments from Current Frame", action: {
                                copyAdjustmentsFromCurrentFrame()
                            })
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars.inverse")
                                Text("Batch")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.blue)
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20)
            
            // Timeline scrubber
            if project.totalFrames > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track background
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 2)
                        
                        // Marked and edited frame indicators
                        ForEach(Array(project.markedFrameIndices), id: \.self) { frameIndex in
                            frameIndicatorView(for: frameIndex, in: geometry)
                        }
                        
                        // Playhead
                        let normalizedPosition = CGFloat(project.currentFrameIndex) / CGFloat(max(1, project.totalFrames - 1))
                        let playheadPosition = normalizedPosition * geometry.size.width
                        
                        // Premium playhead with glow and depth
                        playheadView(at: playheadPosition)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newPosition = max(0, min(geometry.size.width, value.location.x))
                                        let normalizedPosition = newPosition / geometry.size.width
                                        let newFrameIndex = Int(normalizedPosition * CGFloat(project.totalFrames - 1))
                                        
                                        if newFrameIndex != project.currentFrameIndex && newFrameIndex < project.totalFrames {
                                            project.updateCurrentFrame(newFrameIndex)
                                            
                                            // Light haptic feedback
                                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                            impactFeedback.impactOccurred(intensity: 0.3)
                                        }
                                    }
                            )
                    }
                }
                .frame(height: 40)
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 16)
        .background(.white)
    }
    
    @ViewBuilder
    private var bottomToolbar: some View {
        HStack {
            Spacer()
            
            // Colorful Adjust button
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()
                
                selectedAdjustmentCategory = .adjust
                selectedControl = nil // Don't auto-select any control
                print("🎨 Opening Adjustments!")
                withAnimation(.easeInOut(duration: 0.3)) {
                    isShowingAdjustments = true
                }
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Adjust")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 18)
                .background(Color.blue)
                .cornerRadius(25)
                .shadow(color: .blue.opacity(0.5), radius: 8, x: 0, y: 4)
            }
            
            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.bottom, 30)
        .background(.black)
    }
    
    @ViewBuilder
    private var adjustmentControlsArea: some View {
        VStack(spacing: 20) {
            // Enhanced back button and mode indicator
            HStack {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    print("🔙 Going back to frames!")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingAdjustments = false
                        selectedControl = nil
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                        Text("Back to Frames")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.purple)
                    .cornerRadius(25)
                    .shadow(color: .purple.opacity(0.4), radius: 6, x: 0, y: 3)
                }
                
                Spacer()
                
                // Colorful mode indicator
                VStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(project.currentFrameIsMarked ? Color.orange : Color.green)
                            .frame(width: 12, height: 12)
                        
                        Text(project.currentFrameIsMarked ? "Frame Edit" : "Global Edit")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(project.currentFrameIsMarked ? .orange : .green)
                    }
                    
                    if project.markedFrameIndices.count > 0 {
                        Text("\(project.markedFrameIndices.count) marked")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
                
                if project.markedFrameIndices.count > 0 {
                    Button("Clear All") {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        project.clearAllMarkedFrames()
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(15)
                    .shadow(color: .red.opacity(0.4), radius: 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            // Simple colorful help text
            if selectedControl == nil {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.blue)
                        
                        Text("Select a control to start adjusting")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                    }
                    
                    Text("Tap any button: Temperature, Exposure, Shadow, Brilliance, Brightness, Contrast, or Saturation")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 20)
            }
            
            // All control buttons in one scrollable row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(selectedAdjustmentCategory.controls) { control in
                        circularControlButton(control: control)
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // Selected control adjustment
            if let selectedControl = selectedControl {
                VStack(spacing: 16) {
                    Text(selectedControl.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                    
                    // Info about current editing mode
                    if project.currentFrameIsMarked {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text("Adjusting this specific frame only")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.orange.opacity(0.15))
                        .cornerRadius(8)
                    } else if project.markedFrameIndices.count > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Global adjustments (won't affect marked frames)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.blue.opacity(0.15))
                        .cornerRadius(8)
                    }
                    
                    // Slider interface for adjustments
                    let binding = getControlBinding(for: selectedControl)
                    let range = getControlRange(for: selectedControl)
                    
                    VStack(spacing: 12) {
                        // Value display and range labels
                        HStack {
                            Text("\(Int(range.lowerBound))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.black.opacity(0.6))
                            
                            Spacer()
                            
                            Text("\(Int(binding.wrappedValue))")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black)
                                .cornerRadius(10)
                            
                            Spacer()
                            
                            Text("\(Int(range.upperBound))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.black.opacity(0.6))
                        }
                        .padding(.horizontal, 40)
                        
                        // Simple working slider
                        Slider(value: binding, in: range) { editing in
                            isDraggingSlider = editing
                            if editing {
                                saveCurrentState()
                                print("🎛️ Started editing \(selectedControl.title)")
                            } else {
                                print("🎛️ Finished editing \(selectedControl.title) = \(binding.wrappedValue)")
                            }
                            updateLivePreview()
                        }
                        .accentColor(.blue)
                        .padding(.horizontal, 30)
                        
                        // Colorful reset button
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            resetControl(selectedControl)
                            updateLivePreview()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset \(selectedControl.title)")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .cornerRadius(16)
                            .shadow(color: .orange.opacity(0.3), radius: 4)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .background(.white)
    }
    
    @ViewBuilder
    private func circularControlButton(control: AdjustmentControl) -> some View {
        let isSelected = selectedControl?.id == control.id
        
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
            
            selectedControl = control
            print("✅ \(control.title) SELECTED!")
            print("🎯 Mode: \(project.currentFrameIsMarked ? "Frame Edit" : "Global Edit")")
        }) {
            VStack(spacing: 6) {
                ZStack {
                    // Simple, working button design
                    Rectangle()
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 75, height: 55)
                        .cornerRadius(12)
                    
                    Image(systemName: control.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isSelected ? .white : .black)
                }
                
                Text(control.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .blue : .black)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private func toolbarButton(icon: String, title: String, isSelected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            // Haptic feedback on button tap
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            action()
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? .orange : .white)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .orange : .white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isSelected ? .black : .black.opacity(0.8))
            .cornerRadius(25)
            .shadow(color: .black.opacity(0.2), radius: 4)
        }
    }
    
    private func getControlValue(for control: AdjustmentControl) -> Double {
        let adjustments = project.currentFrameIsMarked ? (project.currentFrame?.adjustments ?? project.globalAdjustments) : project.globalAdjustments
        
        switch control.title {
        case "Temperature": return adjustments.temperature
        case "Exposure": return adjustments.exposure * 50 // Scale to -100...100 range
        case "Shadow": return adjustments.shadows
        case "Brilliance": return adjustments.vibrancy
        case "Brightness": return adjustments.brightness
        case "Contrast": return adjustments.contrast
        case "Saturation": return adjustments.saturation
        default: return 0.0
        }
    }
    
    private func getControlBinding(for control: AdjustmentControl) -> Binding<Double> {
        return Binding<Double>(
            get: {
                // Get the current value based on mode
                if self.project.currentFrameIsMarked {
                    // Frame-specific mode
                    guard let frameAdjustments = self.project.currentFrame?.adjustments else {
                        return 0.0
                    }
                    
                    switch control.title {
                    case "Temperature": return frameAdjustments.temperature
                    case "Exposure": return frameAdjustments.exposure * 50
                    case "Shadow": return frameAdjustments.shadows
                    case "Brilliance": return frameAdjustments.vibrancy
                    case "Brightness": return frameAdjustments.brightness
                    case "Contrast": return frameAdjustments.contrast
                    case "Saturation": return frameAdjustments.saturation
                    default: return 0.0
                    }
                } else {
                    // Global mode
                    switch control.title {
                    case "Temperature": return self.project.globalAdjustments.temperature
                    case "Exposure": return self.project.globalAdjustments.exposure * 50
                    case "Shadow": return self.project.globalAdjustments.shadows
                    case "Brilliance": return self.project.globalAdjustments.vibrancy
                    case "Brightness": return self.project.globalAdjustments.brightness
                    case "Contrast": return self.project.globalAdjustments.contrast
                    case "Saturation": return self.project.globalAdjustments.saturation
                    default: return 0.0
                    }
                }
            },
            set: { newValue in
                print("🎛️ SETTING \(control.title) to: \(newValue)")
                print("🎯 Current mode: \(self.project.currentFrameIsMarked ? "Frame Edit" : "Global Edit")")
                print("📊 Frame index: \(self.project.currentFrameIndex)")
                
                // Force UI update by triggering objectWillChange
                self.project.objectWillChange.send()
                
                if self.project.currentFrameIsMarked {
                    // Frame-specific adjustment - directly modify the frame
                    guard self.project.currentFrameIndex < self.project.frames.count else {
                        print("❌ Invalid frame index: \(self.project.currentFrameIndex)")
                        return
                    }
                    
                    switch control.title {
                    case "Temperature": 
                        self.project.frames[self.project.currentFrameIndex].adjustments.temperature = newValue
                        print("✅ Set frame temperature to \(newValue)")
                    case "Exposure": 
                        self.project.frames[self.project.currentFrameIndex].adjustments.exposure = newValue / 50
                        print("✅ Set frame exposure to \(newValue / 50)")
                    case "Shadow": 
                        self.project.frames[self.project.currentFrameIndex].adjustments.shadows = newValue
                        print("✅ Set frame shadows to \(newValue)")
                    case "Brilliance": 
                        self.project.frames[self.project.currentFrameIndex].adjustments.vibrancy = newValue
                        print("✅ Set frame vibrancy to \(newValue)")
                    case "Brightness": 
                        self.project.frames[self.project.currentFrameIndex].adjustments.brightness = newValue
                        print("✅ Set frame brightness to \(newValue)")
                    case "Contrast": 
                        self.project.frames[self.project.currentFrameIndex].adjustments.contrast = newValue
                        print("✅ Set frame contrast to \(newValue)")
                    case "Saturation": 
                        self.project.frames[self.project.currentFrameIndex].adjustments.saturation = newValue
                        print("✅ Set frame saturation to \(newValue)")
                    default: 
                        print("❌ Unknown control: \(control.title)")
                    }
                } else {
                    // Global adjustment - directly modify global adjustments
                    switch control.title {
                    case "Temperature": 
                        self.project.globalAdjustments.temperature = newValue
                        print("✅ Set global temperature to \(newValue)")
                    case "Exposure": 
                        self.project.globalAdjustments.exposure = newValue / 50
                        print("✅ Set global exposure to \(newValue / 50)")
                    case "Shadow": 
                        self.project.globalAdjustments.shadows = newValue
                        print("✅ Set global shadows to \(newValue)")
                    case "Brilliance": 
                        self.project.globalAdjustments.vibrancy = newValue
                        print("✅ Set global vibrancy to \(newValue)")
                    case "Brightness": 
                        self.project.globalAdjustments.brightness = newValue
                        print("✅ Set global brightness to \(newValue)")
                    case "Contrast": 
                        self.project.globalAdjustments.contrast = newValue
                        print("✅ Set global contrast to \(newValue)")
                    case "Saturation": 
                        self.project.globalAdjustments.saturation = newValue
                        print("✅ Set global saturation to \(newValue)")
                    default: 
                        print("❌ Unknown control: \(control.title)")
                    }
                }
                
                // Force update the live preview immediately
                print("🎨 Updating live preview...")
                DispatchQueue.main.async {
                    self.updateLivePreview()
                }
            }
        )
    }
    
    private func getControlRange(for control: AdjustmentControl) -> ClosedRange<Double> {
        switch control.title {
        case "Temperature": return -100...100
        case "Exposure": return -100...100
        case "Shadow": return -100...100
        case "Brilliance": return -100...100
        case "Brightness": return -100...100
        case "Contrast": return -100...100
        case "Saturation": return -100...100
        default: return -100...100
        }
    }
    
    private func updateControlValue(control: AdjustmentControl, value: Double) {
        // The binding handles the update automatically, but we can add haptic feedback here
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        if !isDraggingSlider {
            impactFeedback.impactOccurred(intensity: 0.3)
        }
    }
    
    
    private func resetCurrentAdjustments() {
        // Reset adjustments for current frame if marked, otherwise reset global
        if project.currentFrameIsMarked {
            let resetAdjustments = AdjustmentSet()
            project.updateFrameAdjustments(resetAdjustments, for: project.currentFrameIndex)
        } else {
            project.globalAdjustments.reset()
        }
        
        // Update the live preview
        if let currentFrame = project.currentFrame {
            if let thumbnail = currentFrame.thumbnail {
                let ciImage = CIImage(image: thumbnail) ?? CIImage()
                imageProcessor.setBaseImage(ciImage)
                let adjustmentsToUse = project.currentFrameIsMarked ? 
                    (project.currentFrame?.adjustments ?? project.globalAdjustments) : 
                    project.globalAdjustments
                imageProcessor.processImageLive(adjustmentsToUse)
            }
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func updateLivePreview() {
        print("🎨 UpdateLivePreview called")
        
        // Update the live preview with current adjustments
        guard let currentFrame = project.currentFrame else {
            print("❌ No current frame available")
            return
        }
        
        guard let thumbnail = currentFrame.thumbnail else {
            print("❌ No thumbnail available for current frame")
            return
        }
        
        let ciImage = CIImage(image: thumbnail) ?? CIImage()
        print("📸 Setting base image with size: \(ciImage.extent)")
        imageProcessor.setBaseImage(ciImage)
        
        // Determine which adjustments to use
        let adjustmentsToUse: AdjustmentSet
        if project.currentFrameIsMarked {
            adjustmentsToUse = project.currentFrame?.adjustments ?? AdjustmentSet()
            print("🎯 Using frame-specific adjustments")
        } else {
            adjustmentsToUse = project.globalAdjustments
            print("🌐 Using global adjustments")
        }
        
        // Print current adjustment values for debugging
        print("📊 Current adjustments - Temp: \(adjustmentsToUse.temperature), Exp: \(adjustmentsToUse.exposure), Shadows: \(adjustmentsToUse.shadows)")
        print("📊 Brightness: \(adjustmentsToUse.brightness), Contrast: \(adjustmentsToUse.contrast), Saturation: \(adjustmentsToUse.saturation)")
        
        // Process the image with current adjustments
        imageProcessor.processImageLive(adjustmentsToUse)
        print("✅ Live preview processing started")
    }
    
    // MARK: - Undo/Redo Functionality
    private func saveCurrentState() {
        let currentState = project.currentFrameIsMarked ? 
            (project.currentFrame?.adjustments ?? project.globalAdjustments) :
            project.globalAdjustments
        
        undoStack.append(currentState.copy())
        redoStack.removeAll() // Clear redo stack when new change is made
        
        // Limit undo stack to 20 items for memory management
        if undoStack.count > 20 {
            undoStack.removeFirst()
        }
    }
    
    private func undoLastChange() {
        guard !undoStack.isEmpty else { return }
        
        // Save current state to redo stack
        let currentState = project.currentFrameIsMarked ? 
            (project.currentFrame?.adjustments ?? project.globalAdjustments) :
            project.globalAdjustments
        redoStack.append(currentState.copy())
        
        // Restore previous state
        let previousState = undoStack.removeLast()
        if project.currentFrameIsMarked {
            project.updateFrameAdjustments(previousState, for: project.currentFrameIndex)
        } else {
            project.globalAdjustments = previousState
        }
        
        updateLivePreview()
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func redoLastChange() {
        guard !redoStack.isEmpty else { return }
        
        // Save current state to undo stack
        let currentState = project.currentFrameIsMarked ? 
            (project.currentFrame?.adjustments ?? project.globalAdjustments) :
            project.globalAdjustments
        undoStack.append(currentState.copy())
        
        // Restore next state
        let nextState = redoStack.removeLast()
        if project.currentFrameIsMarked {
            project.updateFrameAdjustments(nextState, for: project.currentFrameIndex)
        } else {
            project.globalAdjustments = nextState
        }
        
        updateLivePreview()
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    // MARK: - Batch Operations
    private func applyCurrentAdjustmentsToMarkedFrames() {
        let currentAdjustments = project.currentFrameIsMarked ? 
            (project.currentFrame?.adjustments ?? project.globalAdjustments) :
            project.globalAdjustments
        
        for frameIndex in project.markedFrameIndices {
            project.updateFrameAdjustments(currentAdjustments.copy(), for: frameIndex)
        }
        
        updateLivePreview()
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func resetAllMarkedFrames() {
        let resetAdjustments = AdjustmentSet()
        
        for frameIndex in project.markedFrameIndices {
            project.updateFrameAdjustments(resetAdjustments, for: frameIndex)
        }
        
        updateLivePreview()
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func copyAdjustmentsFromCurrentFrame() {
        guard let currentFrameAdjustments = project.currentFrame?.adjustments else { return }
        
        // Store the adjustments for pasting to other frames
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // For now, immediately apply to all marked frames
        for frameIndex in project.markedFrameIndices {
            if frameIndex != project.currentFrameIndex {
                project.updateFrameAdjustments(currentFrameAdjustments.copy(), for: frameIndex)
            }
        }
        
        updateLivePreview()
    }
    
    // MARK: - Marked Frame Navigation
    private func hasPreviousMarkedFrame() -> Bool {
        let sortedIndices = project.markedFrameIndices.sorted()
        guard let currentIndex = sortedIndices.firstIndex(of: project.currentFrameIndex) else {
            // Current frame is not marked, check if there are any marked frames before current
            return sortedIndices.contains { $0 < project.currentFrameIndex }
        }
        return currentIndex > 0
    }
    
    private func hasNextMarkedFrame() -> Bool {
        let sortedIndices = project.markedFrameIndices.sorted()
        guard let currentIndex = sortedIndices.firstIndex(of: project.currentFrameIndex) else {
            // Current frame is not marked, check if there are any marked frames after current
            return sortedIndices.contains { $0 > project.currentFrameIndex }
        }
        return currentIndex < sortedIndices.count - 1
    }
    
    private func goToPreviousMarkedFrame() {
        let sortedIndices = project.markedFrameIndices.sorted()
        
        if let currentIndex = sortedIndices.firstIndex(of: project.currentFrameIndex) {
            // Current frame is marked, go to previous marked frame
            if currentIndex > 0 {
                let previousFrameIndex = sortedIndices[currentIndex - 1]
                project.updateCurrentFrame(previousFrameIndex)
                updateLivePreview()
                
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        } else {
            // Current frame is not marked, find the closest previous marked frame
            if let previousFrameIndex = sortedIndices.last(where: { $0 < project.currentFrameIndex }) {
                project.updateCurrentFrame(previousFrameIndex)
                updateLivePreview()
                
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
    }
    
    private func goToNextMarkedFrame() {
        let sortedIndices = project.markedFrameIndices.sorted()
        
        if let currentIndex = sortedIndices.firstIndex(of: project.currentFrameIndex) {
            // Current frame is marked, go to next marked frame
            if currentIndex < sortedIndices.count - 1 {
                let nextFrameIndex = sortedIndices[currentIndex + 1]
                project.updateCurrentFrame(nextFrameIndex)
                updateLivePreview()
                
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        } else {
            // Current frame is not marked, find the closest next marked frame
            if let nextFrameIndex = sortedIndices.first(where: { $0 > project.currentFrameIndex }) {
                project.updateCurrentFrame(nextFrameIndex)
                updateLivePreview()
                
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
    }
    
    private func resetControl(_ control: AdjustmentControl) {
        // Reset specific control for current frame if marked, otherwise global
        if project.currentFrameIsMarked {
            guard var frameAdjustments = project.currentFrame?.adjustments else { return }
            
            // Reset specific control
            switch control.title {
            case "Temperature": frameAdjustments.temperature = 0.0
            case "Exposure": frameAdjustments.exposure = 0.0
            case "Shadow": frameAdjustments.shadows = 0.0
            case "Brilliance": frameAdjustments.vibrancy = 0.0
            case "Brightness": frameAdjustments.brightness = 0.0
            case "Contrast": frameAdjustments.contrast = 0.0
            case "Saturation": frameAdjustments.saturation = 0.0
            default: break
            }
            
            project.updateFrameAdjustments(frameAdjustments, for: project.currentFrameIndex)
        } else {
            // Reset specific global control
            switch control.title {
            case "Temperature": project.globalAdjustments.temperature = 0.0
            case "Exposure": project.globalAdjustments.exposure = 0.0
            case "Shadow": project.globalAdjustments.shadows = 0.0
            case "Brilliance": project.globalAdjustments.vibrancy = 0.0
            case "Brightness": project.globalAdjustments.brightness = 0.0
            case "Contrast": project.globalAdjustments.contrast = 0.0
            case "Saturation": project.globalAdjustments.saturation = 0.0
            default: break
            }
        }
    }
    
    @ViewBuilder
    private func frameIndicatorView(for frameIndex: Int, in geometry: GeometryProxy) -> some View {
        let markedNormalizedPosition = CGFloat(frameIndex) / CGFloat(max(1, project.totalFrames - 1))
        let markedPosition = markedNormalizedPosition * geometry.size.width
        
        // Check if frame has adjustments
        let hasAdjustments: Bool = {
            guard frameIndex < project.frames.count else { return false }
            let frame = project.frames[frameIndex]
            return !frame.adjustments.isEmpty
        }()
        
        // Different indicators for different states
        let isMarked = project.markedFrameIndices.contains(frameIndex)
        
        VStack(spacing: 2) {
            // Top indicator - shows editing status
            if hasAdjustments {
                // Green indicator for edited frames
                Rectangle()
                    .fill(LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 6, height: 10)
                    .cornerRadius(3)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .shadow(color: .green.opacity(0.6), radius: 3)
            } else {
                // Gray indicator for unedited frames
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(width: 4, height: 6)
                    .cornerRadius(2)
            }
            
            // Bottom indicator - shows marked status
            if isMarked {
                Circle()
                    .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .stroke(.white, lineWidth: 1)
                    )
                    .shadow(color: .orange.opacity(0.8), radius: 2)
            }
        }
        .offset(x: markedPosition - 3, y: -12)
        .animation(.easeInOut(duration: 0.2), value: hasAdjustments)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isMarked)
    }
    
    @ViewBuilder
    private func playheadView(at position: CGFloat) -> some View {
        // Create gradients separately to avoid complex expressions
        let markedGradient = LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        let normalGradient = LinearGradient(colors: [.white, .gray.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        let selectedGradient = project.currentFrameIsMarked ? markedGradient : normalGradient
        
        // Calculate colors separately
        let shadowColor = project.currentFrameIsMarked ? Color.yellow.opacity(0.6) : Color.black.opacity(0.4)
        let strokeColor = project.currentFrameIsMarked ? Color.yellow : Color.white
        let scale: CGFloat = project.currentFrameIsMarked ? 1.2 : 1.0
        
        ZStack {
            Circle()
                .fill(selectedGradient)
                .frame(width: 20, height: 20)
                .shadow(color: shadowColor, radius: 6)
            
            Circle()
                .stroke(strokeColor, lineWidth: 2)
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.2), radius: 2)
        }
        .scaleEffect(scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: project.currentFrameIsMarked)
        .offset(x: position - 10)
    }
    
    @ViewBuilder
    private func controlButtonContent(for control: AdjustmentControl) -> some View {
        let isSelected = selectedControl?.id == control.id
        
        // Create gradients separately
        let selectedBgGradient = LinearGradient(colors: [.yellow.opacity(0.3), .orange.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        let normalBgGradient = LinearGradient(colors: [.gray.opacity(0.15), .black.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
        let bgGradient = isSelected ? selectedBgGradient : normalBgGradient
        
        let selectedBorderGradient = LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        let normalBorderGradient = LinearGradient(colors: [.gray.opacity(0.4), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        let borderGradient = isSelected ? selectedBorderGradient : normalBorderGradient
        
        let selectedIconGradient = LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        let normalIconGradient = LinearGradient(colors: [.black, .gray.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        let iconGradient = isSelected ? selectedIconGradient : normalIconGradient
        
        let selectedTextGradient = LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
        let normalTextGradient = LinearGradient(colors: [.black, .gray], startPoint: .leading, endPoint: .trailing)
        let textGradient = isSelected ? selectedTextGradient : normalTextGradient
        
        VStack(spacing: 10) {
            ZStack {
                // Premium gradient background with depth
                Circle()
                    .fill(bgGradient)
                    .frame(width: 75, height: 75)
                    .shadow(color: isSelected ? .yellow.opacity(0.4) : .black.opacity(0.1), radius: 8)
                
                // Premium border with animated glow
                Circle()
                    .stroke(borderGradient, lineWidth: isSelected ? 3 : 1.5)
                    .frame(width: 75, height: 75)
                    .shadow(color: isSelected ? .yellow.opacity(0.6) : .clear, radius: 4)
                
                // Premium icon with depth and glow
                Image(systemName: control.icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(iconGradient)
                    .shadow(color: isSelected ? .yellow.opacity(0.3) : .black.opacity(0.2), radius: 2, x: 0, y: 1)
            }
            
            Text(control.title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(textGradient)
                .shadow(color: isSelected ? .yellow.opacity(0.3) : .clear, radius: 1)
        }
    }
}

struct MetalPreviewView: UIViewRepresentable {
    let ciImage: CIImage
    let adjustments: AdjustmentSet
    let metalRenderer: MetalRenderer
    let imageProcessor: LiveImageProcessor
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        metalRenderer.setupMTKView(mtkView)
        mtkView.delegate = context.coordinator
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateImage(ciImage, adjustments: adjustments)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(metalRenderer: metalRenderer, imageProcessor: imageProcessor)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        let metalRenderer: MetalRenderer
        let imageProcessor: LiveImageProcessor
        private var currentImage: CIImage?
        private var currentAdjustments = AdjustmentSet()
        
        init(metalRenderer: MetalRenderer, imageProcessor: LiveImageProcessor) {
            self.metalRenderer = metalRenderer
            self.imageProcessor = imageProcessor
            super.init()
        }
        
        func updateImage(_ image: CIImage, adjustments: AdjustmentSet) {
            currentImage = image
            currentAdjustments = adjustments
            imageProcessor.setBaseImage(image)
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let image = currentImage else { return }
            
            let processedImage = imageProcessor.processImageSync(image, adjustments: currentAdjustments)
            metalRenderer.renderImage(processedImage, to: drawable)
        }
    }
}

enum AdjustmentCategory: CaseIterable {
    case adjust
    
    var title: String {
        switch self {
        case .adjust: return "Adjustments"
        }
    }
    
    var controls: [AdjustmentControl] {
        switch self {
        case .adjust:
            return [
                AdjustmentControl(icon: "thermometer", title: "Temperature"),
                AdjustmentControl(icon: "sun.max.fill", title: "Exposure"),
                AdjustmentControl(icon: "moon.fill", title: "Shadow"),
                AdjustmentControl(icon: "sparkles", title: "Brilliance"),
                AdjustmentControl(icon: "lightbulb.fill", title: "Brightness"),
                AdjustmentControl(icon: "circle.righthalf.filled", title: "Contrast"),
                AdjustmentControl(icon: "paintpalette.fill", title: "Saturation")
            ]
        }
    }
}

struct AdjustmentControl: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
}

#Preview {
    AppleStyleVideoEditor(project: VideoProject())
}