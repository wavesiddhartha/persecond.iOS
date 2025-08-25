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
    
    @Environment(\.presentationMode) var presentationMode
    
    init(project: VideoProject) {
        self.project = project
        self._videoExporter = StateObject(wrappedValue: VideoExporter(imageProcessor: LiveImageProcessor(metalDevice: MTLCreateSystemDefaultDevice()!)))
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
            .navigationTitle("Export Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if videoExporter.isExporting {
                            videoExporter.cancelExport()
                        }
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !videoExporter.isExporting {
                        Button("Export") {
                            startExport()
                        }
                        .disabled(exportURL == nil)
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
        .background(.regularMaterial)
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
                .background(.thinMaterial)
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
            .background(.regularMaterial)
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
                    .background(.thinMaterial)
                    .cornerRadius(8)
                } else {
                    Button(action: { showingFilePicker = true }) {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("Choose Export Location")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.thinMaterial)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
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
            .background(.regularMaterial)
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var exportProgressView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            
            VStack(spacing: 16) {
                ProgressView(value: videoExporter.exportProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                
                Text("\(Int(videoExporter.exportProgress * 100))%")
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 40)
            
            
            VStack(spacing: 8) {
                Text("Exporting Video")
                    .font(.headline)
                
                Text(videoExporter.exportStatus)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
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
    
    private func startExport() {
        guard let outputURL = exportURL else { return }
        
        Task {
            do {
                try await videoExporter.exportVideo(
                    project: project,
                    exportSettings: selectedPreset.settings,
                    outputURL: outputURL
                )
            } catch {
                print("Export failed: \(error)")
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
            .background(isSelected ? .blue.opacity(0.1) : .thinMaterial)
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


#Preview {
    ExportView(project: VideoProject())
}