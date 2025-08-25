import SwiftUI
import AVFoundation

struct VideoTimelineView: View {
    @ObservedObject var project: VideoProject
    @State private var isDraggingPlayhead: Bool = false
    @State private var isDraggingStartHandle: Bool = false
    @State private var isDraggingEndHandle: Bool = false
    @State private var dragOffset: CGFloat = 0
    
    private let hapticFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    
    private let frameHeight: CGFloat = 60
    private let frameSpacing: CGFloat = 2
    private let handleWidth: CGFloat = 20
    
    var body: some View {
        VStack(spacing: 12) {
            
            timeDisplay
            
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    
                    frameStrip(geometry: geometry)
                    
                    
                    selectionOverlay(geometry: geometry)
                    
                    
                    playheadIndicator(geometry: geometry)
                    
                    
                    rangeHandles(geometry: geometry)
                }
                .clipped()
            }
            .frame(height: frameHeight + 20)
            
            
            controlsRow
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .onAppear {
            hapticFeedback.prepare()
            impactFeedback.prepare()
        }
    }
    
    @ViewBuilder
    private var timeDisplay: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(currentTime))
                    .font(.title2.monospacedDigit())
                    .fontWeight(.medium)
                
                Text("Frame \(project.currentFrameIndex + 1) of \(project.totalFrames)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(project.selectedDuration))
                    .font(.headline.monospacedDigit())
                
                Text("\(selectedFrameCount) frames selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func frameStrip(geometry: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: frameSpacing) {
                    ForEach(Array(project.frames.enumerated()), id: \.offset) { index, frame in
                        FrameThumbnailView(
                            frame: frame,
                            isSelected: index == project.currentFrameIndex,
                            isInSelectedRange: isFrameInSelectedRange(index),
                            size: CGSize(width: frameHeight * 1.5, height: frameHeight)
                        )
                        .id(index)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                project.updateCurrentFrame(index)
                            }
                            hapticFeedback.selectionChanged()
                        }
                    }
                }
                .padding(.horizontal, geometry.size.width / 2)
            }
            .onChange(of: project.currentFrameIndex) { oldValue, newValue in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
    
    @ViewBuilder
    private func selectionOverlay(geometry: GeometryProxy) -> some View {
        let totalWidth = geometry.size.width
        let startX = totalWidth * CGFloat(project.selectedRange.lowerBound)
        let endX = totalWidth * CGFloat(project.selectedRange.upperBound)
        let selectionWidth = endX - startX
        
        Rectangle()
            .fill(.blue.opacity(0.2))
            .frame(width: selectionWidth, height: frameHeight + 10)
            .offset(x: startX)
            .overlay(
                Rectangle()
                    .stroke(.blue, lineWidth: 2)
                    .frame(width: selectionWidth, height: frameHeight + 10)
                    .offset(x: startX)
            )
    }
    
    @ViewBuilder
    private func playheadIndicator(geometry: GeometryProxy) -> some View {
        let normalizedPosition = CGFloat(project.currentFrameIndex) / CGFloat(max(1, project.totalFrames - 1))
        let xPosition = geometry.size.width * normalizedPosition
        
        Rectangle()
            .fill(.red)
            .frame(width: 2, height: frameHeight + 20)
            .offset(x: xPosition)
            .overlay(
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                    .offset(x: xPosition, y: -(frameHeight + 20) / 2 - 6)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDraggingPlayhead {
                            isDraggingPlayhead = true
                            impactFeedback.impactOccurred(intensity: 0.5)
                        }
                        
                        let newPosition = max(0, min(geometry.size.width, value.location.x))
                        let normalizedPosition = newPosition / geometry.size.width
                        let newFrameIndex = Int(normalizedPosition * CGFloat(project.totalFrames - 1))
                        
                        if newFrameIndex != project.currentFrameIndex {
                            project.updateCurrentFrame(newFrameIndex)
                            hapticFeedback.selectionChanged()
                        }
                    }
                    .onEnded { _ in
                        isDraggingPlayhead = false
                    }
            )
    }
    
    @ViewBuilder
    private func rangeHandles(geometry: GeometryProxy) -> some View {
        let totalWidth = geometry.size.width
        let startX = totalWidth * CGFloat(project.selectedRange.lowerBound)
        let endX = totalWidth * CGFloat(project.selectedRange.upperBound)
        
        
        RangeHandle(isStart: true, isDragging: isDraggingStartHandle)
            .offset(x: startX - handleWidth / 2)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDraggingStartHandle {
                            isDraggingStartHandle = true
                            impactFeedback.impactOccurred(intensity: 0.5)
                        }
                        
                        let newPosition = max(0, min(endX - 50, value.location.x))
                        let newStartBound = max(0.0, min(0.8, Double(newPosition / totalWidth)))
                        
                        withAnimation(.easeOut(duration: 0.1)) {
                            project.updateSelectedRange(newStartBound...project.selectedRange.upperBound)
                        }
                    }
                    .onEnded { _ in
                        isDraggingStartHandle = false
                        impactFeedback.impactOccurred(intensity: 0.7)
                    }
            )
        
        
        RangeHandle(isStart: false, isDragging: isDraggingEndHandle)
            .offset(x: endX - handleWidth / 2)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDraggingEndHandle {
                            isDraggingEndHandle = true
                            impactFeedback.impactOccurred(intensity: 0.5)
                        }
                        
                        let newPosition = max(startX + 50, min(totalWidth, value.location.x))
                        let newEndBound = max(0.2, min(1.0, Double(newPosition / totalWidth)))
                        
                        withAnimation(.easeOut(duration: 0.1)) {
                            project.updateSelectedRange(project.selectedRange.lowerBound...newEndBound)
                        }
                    }
                    .onEnded { _ in
                        isDraggingEndHandle = false
                        impactFeedback.impactOccurred(intensity: 0.7)
                    }
            )
    }
    
    @ViewBuilder
    private var controlsRow: some View {
        HStack(spacing: 20) {
            
            Button(action: previousFrame) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(Circle().fill(.thinMaterial))
            }
            .disabled(project.currentFrameIndex <= 0)
            
            
            Button(action: nextFrame) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(Circle().fill(.thinMaterial))
            }
            .disabled(project.currentFrameIndex >= project.totalFrames - 1)
            
            Spacer()
            
            
            Button(action: selectAllFrames) {
                Text("Select All")
                    .font(.callout)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .cornerRadius(20)
            }
            
            
            Button(action: fitSelection) {
                Text("Fit")
                    .font(.callout)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .cornerRadius(20)
            }
        }
    }
    
    private var currentTime: CMTime {
        guard project.currentFrameIndex < project.frames.count else { return .zero }
        return project.frames[project.currentFrameIndex].timestamp
    }
    
    private var selectedFrameCount: Int {
        let startIndex = Int(project.selectedRange.lowerBound * Double(project.totalFrames))
        let endIndex = Int(project.selectedRange.upperBound * Double(project.totalFrames))
        return endIndex - startIndex
    }
    
    private func isFrameInSelectedRange(_ index: Int) -> Bool {
        let normalizedIndex = Double(index) / Double(max(1, project.totalFrames - 1))
        return project.selectedRange.contains(normalizedIndex)
    }
    
    private func formatTime(_ time: CMTime) -> String {
        let seconds = time.seconds
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let frames = Int((seconds - Double(Int(seconds))) * Double(project.frameRate))
        
        return String(format: "%02d:%02d:%02d", minutes, remainingSeconds, frames)
    }
    
    private func formatDuration(_ duration: CMTime) -> String {
        let seconds = duration.seconds
        return String(format: "%.2fs", seconds)
    }
    
    private func previousFrame() {
        project.previousFrame()
        hapticFeedback.selectionChanged()
    }
    
    private func nextFrame() {
        project.nextFrame()
        hapticFeedback.selectionChanged()
    }
    
    private func selectAllFrames() {
        withAnimation(.easeInOut(duration: 0.3)) {
            project.updateSelectedRange(0.0...1.0)
        }
        impactFeedback.impactOccurred(intensity: 0.6)
    }
    
    private func fitSelection() {
        withAnimation(.easeInOut(duration: 0.3)) {
            let currentPosition = Double(project.currentFrameIndex) / Double(max(1, project.totalFrames - 1))
            let margin = 0.1
            let start = max(0.0, currentPosition - margin)
            let end = min(1.0, currentPosition + margin)
            project.updateSelectedRange(start...end)
        }
        impactFeedback.impactOccurred(intensity: 0.6)
    }
}

struct FrameThumbnailView: View {
    let frame: FrameAdjustment
    let isSelected: Bool
    let isInSelectedRange: Bool
    let size: CGSize
    
    var body: some View {
        Group {
            if let thumbnail = frame.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.3))
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    isSelected ? .red : isInSelectedRange ? .blue : .clear,
                    lineWidth: isSelected ? 3 : 2
                )
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .cornerRadius(4)
    }
}

struct RangeHandle: View {
    let isStart: Bool
    let isDragging: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            
            Image(systemName: isStart ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill")
                .font(.caption)
                .foregroundColor(.white)
                .padding(4)
                .background(
                    Circle()
                        .fill(.blue)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                )
            
            
            Rectangle()
                .fill(.blue)
                .frame(width: 2, height: 60)
                .scaleEffect(x: isDragging ? 1.5 : 1.0, y: 1.0)
                .animation(.easeInOut(duration: 0.2), value: isDragging)
        }
        .scaleEffect(isDragging ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    }
}

#Preview {
    @State var project = VideoProject()
    
    return VideoTimelineView(project: project)
        .onAppear {
            
            let sampleFrames = (0..<60).map { index in
                FrameAdjustment(
                    frameIndex: index,
                    timestamp: CMTime(seconds: Double(index) * 0.033, preferredTimescale: 600)
                )
            }
            project.addFrames(sampleFrames)
        }
}