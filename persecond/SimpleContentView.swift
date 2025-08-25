import SwiftUI
import PhotosUI
import AVFoundation

struct SimpleContentView: View {
    @StateObject private var project = VideoProject()
    @StateObject private var frameExtractor = VideoFrameExtractor()
    @State private var showingVideoPicker = false
    @State private var showingVideoEditor = false
    @State private var isProcessingVideo = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Full white background covering everything
                Color.white
                    .ignoresSafeArea(.all)
                
                if project.totalFrames > 0 {
                    // Show video editor when video is loaded
                    videoEditorView
                } else {
                    // Show welcome/import screen
                    importView
                }
                
                if isProcessingVideo {
                    processingOverlay
                }
            }
            .navigationBarHidden(project.totalFrames > 0)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingVideoPicker) {
            VideoImportView(
                project: project,
                frameExtractor: frameExtractor,
                isProcessing: $isProcessingVideo
            )
        }
    }
    
    @ViewBuilder
    private var importView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Custom persecond logo matching the design
            persecondLogo
            
            VStack(spacing: 12) {
                Text("Frame-by-frame video editing with live preview")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            }
            
            Spacer()
            
            Button("Import Video") {
                showingVideoPicker = true
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(.black)
            .cornerRadius(25)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea(.all))
        .navigationBarHidden(true)
    }
    
    @ViewBuilder
    private var videoEditorView: some View {
        AppleStyleVideoEditor(project: project)
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
                
                Text("Processing Video...")
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
            .background(Color.black.opacity(0.8))
            .cornerRadius(20)
        }
    }
    
    @ViewBuilder
    private var persecondLogo: some View {
        VStack(spacing: 8) {
            // Main "per" logo text matching your design
            HStack(spacing: 2) {
                Text("per")
                    .font(.system(size: 72, weight: .black, design: .default))
                    .foregroundColor(.black)
            }
            
            // "second" subtitle
            HStack(spacing: 12) {
                ForEach(["s", "e", "c", "o", "n", "d"], id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: 24, weight: .light, design: .default))
                        .foregroundColor(.black)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
    }
}

struct VideoImportView: UIViewControllerRepresentable {
    @ObservedObject var project: VideoProject
    @ObservedObject var frameExtractor: VideoFrameExtractor
    @Binding var isProcessing: Bool
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoImportView
        
        init(_ parent: VideoImportView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            
            if result.itemProvider.hasItemConformingToTypeIdentifier("public.movie") {
                parent.isProcessing = true
                
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
                    if let error = error {
                        print("Error loading video: \(error)")
                        DispatchQueue.main.async {
                            self.parent.isProcessing = false
                        }
                        return
                    }
                    
                    guard let url = url else {
                        DispatchQueue.main.async {
                            self.parent.isProcessing = false
                        }
                        return
                    }
                    
                    // Copy video to documents directory
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
                            
                            // Extract frames
                            Task {
                                do {
                                    let frames = try await self.parent.frameExtractor.extractFrames(from: asset, maxFrames: 120)
                                    await MainActor.run {
                                        self.parent.project.addFrames(frames)
                                        self.parent.isProcessing = false
                                    }
                                } catch {
                                    print("Error extracting frames: \(error)")
                                    await MainActor.run {
                                        self.parent.isProcessing = false
                                    }
                                }
                            }
                        }
                    } catch {
                        print("Error copying video: \(error)")
                        DispatchQueue.main.async {
                            self.parent.isProcessing = false
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SimpleContentView()
}