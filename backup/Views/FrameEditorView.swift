import SwiftUI
import PhotosUI
import AVFoundation

struct FrameEditorView: View {
    @ObservedObject var project: VideoProject
    @StateObject private var frameExtractor = VideoFrameExtractor()
    @StateObject private var metalRenderer: MetalRenderer
    @StateObject private var imageProcessor: LiveImageProcessor
    
    @State private var showingAdjustmentPanel: Bool = false
    @State private var showingTimeline: Bool = true
    @State private var showingExportView: Bool = false
    @State private var isProcessing: Bool = false
    @State private var showingVideoImporter: Bool = false
    
    @Environment(\.presentationMode) var presentationMode
    
    init(project: VideoProject) {
        self.project = project
        
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device not available")
        }
        
        self._metalRenderer = StateObject(wrappedValue: MetalRenderer())
        self._imageProcessor = StateObject(wrappedValue: LiveImageProcessor(metalDevice: metalDevice))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    if project.totalFrames > 0 {
                        livePreviewSection
                    } else {
                        emptyStateView
                    }
                    
                    if showingTimeline && project.totalFrames > 0 {
                        timelineSection
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    if showingAdjustmentPanel && project.totalFrames > 0 {
                        adjustmentPanelSection
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
                
                if isProcessing {
                    processingOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .principal) {
                    Text(project.name.isEmpty ? "Frame Editor" : project.name)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: toggleAdjustmentPanel) {
                            Image(systemName: showingAdjustmentPanel ? "slider.horizontal.3" : "slider.horizontal.3")
                                .foregroundColor(.white)
                        }
                        
                        Button("Export") {
                            showingExportView = true
                        }
                        .foregroundColor(.white)
                        .disabled(project.totalFrames == 0)
                    }
                }
            }
            .onAppear {
                setupInitialState()
            }
        }
        .sheet(isPresented: $showingVideoImporter) {
            VideoImportView(project: project, frameExtractor: frameExtractor)
        }
        .sheet(isPresented: $showingExportView) {
            ExportView(project: project)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    @ViewBuilder
    private var livePreviewSection: some View {
        LivePreviewView(
            project: project,
            renderer: metalRenderer,
            imageProcessor: imageProcessor
        )
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingTimeline.toggle()
                    }
                }
        )
    }
    
    @ViewBuilder
    private var timelineSection: some View {
        VideoTimelineView(project: project)
            .padding(.horizontal)
            .padding(.bottom, showingAdjustmentPanel ? 0 : 20)
    }
    
    @ViewBuilder
    private var adjustmentPanelSection: some View {
        AdjustmentPanelView(
            project: project,
            imageProcessor: imageProcessor
        )
        .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.y > 100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingAdjustmentPanel = false
                        }
                    }
                }
        )
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 30) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            
            VStack(spacing: 12) {
                Text("Import a Video")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Choose a video from your library to start frame-by-frame editing")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: {
                showingVideoImporter = true
            }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Import Video")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text("Processing Frames...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if frameExtractor.isExtracting {
                    VStack(spacing: 8) {
                        Text("Extracting frames from video")
                            .font(.body)
                            .foregroundColor(.gray)
                        
                        ProgressView(value: frameExtractor.extractionProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            .frame(width: 200)
                        
                        Text("\(Int(frameExtractor.extractionProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }
    
    private func setupInitialState() {
        metalRenderer.optimizeForLivePreview()
        
        if let currentFrame = project.currentFrame,
           let image = CIImage(image: currentFrame.thumbnail ?? UIImage()) {
            imageProcessor.setBaseImage(image)
        }
    }
    
    private func toggleAdjustmentPanel() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showingAdjustmentPanel.toggle()
            
            if showingAdjustmentPanel && showingTimeline {
                showingTimeline = false
            } else if !showingAdjustmentPanel && !showingTimeline {
                showingTimeline = true
            }
        }
    }
}

struct VideoImportView: UIViewControllerRepresentable {
    @ObservedObject var project: VideoProject
    @ObservedObject var frameExtractor: VideoFrameExtractor
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoImportView
        
        init(_ parent: VideoImportView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.presentationMode.wrappedValue.dismiss()
                return
            }
            
            if result.itemProvider.hasItemConformingToTypeIdentifier("public.movie") {
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
                    if let error = error {
                        print("Error loading video: \(error)")
                        DispatchQueue.main.async {
                            self.parent.presentationMode.wrappedValue.dismiss()
                        }
                        return
                    }
                    
                    guard let url = url else {
                        DispatchQueue.main.async {
                            self.parent.presentationMode.wrappedValue.dismiss()
                        }
                        return
                    }
                    
                    
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let destURL = documentsPath.appendingPathComponent(url.lastPathComponent)
                    
                    do {
                        if FileManager.default.fileExists(atPath: destURL.path) {
                            try FileManager.default.removeItem(at: destURL)
                        }
                        try FileManager.default.copyItem(at: url, to: destURL)
                        
                        let asset = AVAsset(url: destURL)
                        
                        DispatchQueue.main.async {
                            self.parent.project.originalVideoURL = destURL
                            self.parent.project.asset = asset
                            self.parent.project.duration = asset.duration
                            self.parent.project.name = destURL.deletingPathExtension().lastPathComponent
                            
                            
                            Task {
                                do {
                                    let frames = try await self.parent.frameExtractor.extractFrames(from: asset, maxFrames: 120)
                                    await MainActor.run {
                                        self.parent.project.addFrames(frames)
                                    }
                                } catch {
                                    print("Error extracting frames: \(error)")
                                }
                            }
                            
                            self.parent.presentationMode.wrappedValue.dismiss()
                        }
                    } catch {
                        print("Error copying video: \(error)")
                        DispatchQueue.main.async {
                            self.parent.presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            } else {
                parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

#Preview {
    FrameEditorView(project: VideoProject())
}