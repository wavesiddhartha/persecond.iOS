import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ExportView: View {
    @ObservedObject var project: VideoProject
    @StateObject private var videoExporter: VideoExporter
    @State private var selectedPreset = ExportSettings.presets[1] // 1080p default
    @State private var customSettings = false
    @State private var exportURL: URL?
    @State private var showingFilePicker = false
    @State private var showingShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var showingError = false
    @State private var errorMessage = ""
    
    @Environment(\.dismiss) private var dismiss
    
    init(project: VideoProject) {
        self.project = project
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self._videoExporter = StateObject(wrappedValue: VideoExporter(imageProcessor: LiveImageProcessor(metalDevice: metalDevice)))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if videoExporter.isExporting {
                    exportProgressView
                } else {
                    exportSettingsView
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 1) {
                        Text("per")
                            .font(.system(size: 16, weight: .black))
                        Text("second")
                            .font(.system(size: 10, weight: .light))
                            .offset(y: 1)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if videoExporter.isExporting {
                            videoExporter.cancelExport()
                        }
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !videoExporter.isExporting {
                        Button(action: {
                            print("Export button tapped!")
                            if exportURL == nil {
                                setDefaultExportLocation()
                            }
                            startExport()
                        }) {
                            Text("Export")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.blue)
                                .cornerRadius(20)
                        }
                        .disabled(project.totalFrames == 0)
                    }
                }
            }
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker(allowedContentTypes: [.directory]) { url in
                if let url = url {
                    let filename = "\(project.name)_edited.mov"
                    exportURL = url.appendingPathComponent(filename)
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("Export Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    @ViewBuilder
    private var exportSettingsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                projectSummarySection
                
                Divider()
                
                
                presetSelectionSection
                
                if customSettings {
                    Divider()
                    customSettingsSection
                }
                
                Divider()
                
                
                exportLocationSection
                
                Divider()
                
                
                estimatedFileSizeSection
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var projectSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project Summary")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Project Name:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(project.name)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Total Frames:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(project.totalFrames)")
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Selected Range:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(project.selectedFrames.count) frames")
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Duration:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDuration(project.selectedDuration))
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var presetSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Quality")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(ExportSettings.presets) { preset in
                    PresetSelectionRow(
                        preset: preset,
                        isSelected: selectedPreset.id == preset.id,
                        onTap: { selectedPreset = preset }
                    )
                }
                
                HStack {
                    Button(action: { customSettings.toggle() }) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Custom Settings")
                        }
                        .foregroundColor(.accentColor)
                    }
                    
                    Spacer()
                    
                    if customSettings {
                        Image(systemName: "chevron.up")
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private var customSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Settings")
                .font(.headline)
            
            VStack(spacing: 16) {
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resolution")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    
                    Text("Advanced settings coming soon...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var exportLocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Location")
                .font(.headline)
            
            VStack(spacing: 12) {
                if let url = exportURL {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Save to:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(url.path)
                                .font(.caption)
                                .lineLimit(2)
                        }
                        
                        Spacer()
                        
                        Button("Change") {
                            showingFilePicker = true
                        }
                    }
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 12) {
                        Button(action: { 
                            setDefaultExportLocation() 
                        }) {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text("Use Default Location")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemBlue).opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { showingFilePicker = true }) {
                            HStack {
                                Image(systemName: "folder.badge.plus")
                                Text("Choose Custom Location")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var estimatedFileSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimated File Size")
                .font(.headline)
            
            let estimatedSize = videoExporter.estimateFileSize(for: project, settings: selectedPreset.settings)
            
            HStack {
                Text("Approximate size:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file))
                    .fontWeight(.medium)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var exportProgressView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Processing animation
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(.gray.opacity(0.2), lineWidth: 8)
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .trim(from: 0, to: videoExporter.exportProgress)
                        .stroke(.black, lineWidth: 8)
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: videoExporter.exportProgress)
                    
                    VStack(spacing: 4) {
                        Image(systemName: "video")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.black)
                        
                        Text("\(Int(videoExporter.exportProgress * 100))%")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                    }
                }
                
                VStack(spacing: 12) {
                    Text("Processing Video with Edits")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.black)
                    
                    Text(videoExporter.exportStatus)
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    // Processing steps indicator
                    HStack(spacing: 16) {
                        processingStepView(
                            icon: "photo.on.rectangle",
                            title: "Frames", 
                            isActive: videoExporter.exportProgress < 0.8
                        )
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(.gray)
                        
                        processingStepView(
                            icon: "speaker.wave.2", 
                            title: "Audio", 
                            isActive: videoExporter.exportProgress >= 0.8 && videoExporter.exportProgress < 0.95
                        )
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(.gray)
                        
                        processingStepView(
                            icon: "checkmark.circle", 
                            title: "Finish", 
                            isActive: videoExporter.exportProgress >= 0.95
                        )
                    }
                    .padding(.top, 8)
                }
            }
            
            Spacer()
            
            
            if videoExporter.exportProgress >= 1.0 {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Export Complete!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let url = exportURL {
                        Button(action: {
                            exportedFileURL = url
                            showingShareSheet = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Video")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(.blue)
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.bottom, 40)
            } else {
                Button("Cancel Export") {
                    videoExporter.cancelExport()
                }
                .foregroundColor(.red)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func setDefaultExportLocation() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "\(project.name)_edited_\(timestamp).mov"
        exportURL = documentsPath.appendingPathComponent(filename)
    }
    
    private func startExport() {
        var outputURL = exportURL
        
        if outputURL == nil {
            setDefaultExportLocation()
            outputURL = exportURL
        }
        
        guard let finalOutputURL = outputURL else { 
            print("Failed to set export URL")
            return 
        }
        
        Task {
            do {
                print("Starting export to: \(finalOutputURL.path)")
                print("Project has \(project.totalFrames) frames")
                print("Using preset: \(selectedPreset.name)")
                
                try await videoExporter.exportVideo(
                    project: project,
                    exportSettings: selectedPreset.settings,
                    outputURL: finalOutputURL
                )
                
                // Export successful
                await MainActor.run {
                    exportedFileURL = finalOutputURL
                    print("Export completed successfully!")
                }
                
            } catch {
                print("Export failed with error: \(error)")
                
                // Show error to user
                await MainActor.run {
                    errorMessage = "Export failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
    
    private func formatDuration(_ duration: CMTime) -> String {
        let seconds = duration.seconds
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct PresetSelectionRow: View {
    let preset: ExportPreset
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(Int(preset.settings.resolution.width))×\(Int(preset.settings.resolution.height)) • \(Int(preset.settings.videoBitrate / 1_000_000))Mbps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding()
            .background(isSelected ? .blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? .blue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onDocumentPicked: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onDocumentPicked(urls.first)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onDocumentPicked(nil)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Helper view for processing steps
extension ExportView {
    @ViewBuilder
    private func processingStepView(icon: String, title: String, isActive: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isActive ? .black : .gray)
                .frame(width: 24, height: 24)
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? .black : .gray)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isActive ? .black.opacity(0.1) : .clear)
        .cornerRadius(8)
        .scaleEffect(isActive ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

#Preview {
    ExportView(project: VideoProject())
}