import Foundation
import CoreImage
import Combine
import UIKit

@MainActor
class FrameEditorViewModel: ObservableObject {
    
    @Published var currentProject: VideoProject
    @Published var isLivePreviewEnabled: Bool = true
    @Published var previewQuality: PreviewQuality = .high
    @Published var processingStatus: String = "Ready"
    @Published var undoStack: [AdjustmentSet] = []
    @Published var redoStack: [AdjustmentSet] = []
    @Published var isProcessingFrame: Bool = false
    @Published var frameProcessingProgress: Double = 0.0
    
    private let imageProcessor: LiveImageProcessor
    private let maxUndoSteps = 50
    private var cancellables = Set<AnyCancellable>()
    private let adjustmentDebouncer = PassthroughSubject<AdjustmentSet, Never>()
    
    var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    var hasUnsavedChanges: Bool {
        !areAdjustmentsDefault(currentProject.globalAdjustments)
    }
    
    init(project: VideoProject, imageProcessor: LiveImageProcessor) {
        self.currentProject = project
        self.imageProcessor = imageProcessor
        
        setupObservers()
        setupDebouncedAdjustments()
    }
    
    private func setupObservers() {
        currentProject.$globalAdjustments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] adjustments in
                self?.handleAdjustmentChange(adjustments)
            }
            .store(in: &cancellables)
        
        currentProject.$currentFrameIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePreviewForCurrentFrame()
            }
            .store(in: &cancellables)
        
        imageProcessor.$processedImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                if image != nil {
                    self?.processingStatus = "Live preview updated"
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupDebouncedAdjustments() {
        adjustmentDebouncer
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] adjustments in
                self?.processLivePreview(adjustments)
            }
            .store(in: &cancellables)
    }
    
    private func handleAdjustmentChange(_ adjustments: AdjustmentSet) {
        if isLivePreviewEnabled {
            adjustmentDebouncer.send(adjustments)
        }
    }
    
    private func processLivePreview(_ adjustments: AdjustmentSet) {
        guard let currentFrame = currentProject.currentFrame,
              let thumbnail = currentFrame.thumbnail,
              let ciImage = CIImage(image: thumbnail) else {
            return
        }
        
        imageProcessor.setBaseImage(ciImage)
        imageProcessor.processImageLive(adjustments)
    }
    
    func updatePreviewForCurrentFrame() {
        guard let currentFrame = currentProject.currentFrame,
              let thumbnail = currentFrame.thumbnail,
              let ciImage = CIImage(image: thumbnail) else {
            return
        }
        
        imageProcessor.setBaseImage(ciImage)
        
        if isLivePreviewEnabled {
            imageProcessor.processImageLive(currentProject.globalAdjustments)
        }
        
        processingStatus = "Frame \(currentProject.currentFrameIndex + 1) loaded"
    }
    
    func applyAdjustmentsToCurrentFrame() {
        guard let currentFrame = currentProject.currentFrame else { return }
        
        saveToUndoStack()
        
        var updatedFrame = currentFrame
        updatedFrame.updateAdjustments(currentProject.globalAdjustments)
        
        if let index = currentProject.frames.firstIndex(where: { $0.id == currentFrame.id }) {
            currentProject.frames[index] = updatedFrame
        }
        
        processingStatus = "Adjustments applied to frame \(currentProject.currentFrameIndex + 1)"
    }
    
    func applyAdjustmentsToSelectedFrames() async {
        let selectedFrames = currentProject.selectedFrames
        let totalFrames = selectedFrames.count
        
        guard totalFrames > 0 else { return }
        
        isProcessingFrame = true
        frameProcessingProgress = 0.0
        
        saveToUndoStack()
        
        for (index, frame) in selectedFrames.enumerated() {
            var updatedFrame = frame
            updatedFrame.updateAdjustments(currentProject.globalAdjustments)
            
            if let projectIndex = currentProject.frames.firstIndex(where: { $0.id == frame.id }) {
                currentProject.frames[projectIndex] = updatedFrame
            }
            
            await MainActor.run {
                frameProcessingProgress = Double(index + 1) / Double(totalFrames)
                processingStatus = "Processing frame \(index + 1) of \(totalFrames)"
            }
            
            
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        isProcessingFrame = false
        processingStatus = "Applied adjustments to \(totalFrames) frames"
    }
    
    func resetCurrentFrameAdjustments() {
        guard currentProject.currentFrame != nil else { return }
        
        saveToUndoStack()
        currentProject.globalAdjustments.reset()
        processingStatus = "Adjustments reset"
    }
    
    func autoAdjustCurrentFrame() async {
        guard let currentFrame = currentProject.currentFrame,
              let thumbnail = currentFrame.thumbnail,
              let ciImage = CIImage(image: thumbnail) else { return }
        
        saveToUndoStack()
        
        let autoAdjustments = await Task {
            return imageProcessor.generateAutoAdjustments(for: ciImage)
        }.value
        
        await MainActor.run {
            currentProject.updateGlobalAdjustments(autoAdjustments)
            processingStatus = "Auto adjustments applied"
        }
    }
    
    func copyAdjustmentsToClipboard() {
        let adjustments = currentProject.globalAdjustments
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(adjustments)
            UIPasteboard.general.setData(data, forPasteboardType: "com.persecond.adjustments")
            processingStatus = "Adjustments copied to clipboard"
        } catch {
            processingStatus = "Failed to copy adjustments"
        }
    }
    
    func pasteAdjustmentsFromClipboard() {
        guard let data = UIPasteboard.general.data(forPasteboardType: "com.persecond.adjustments") else {
            processingStatus = "No adjustments found in clipboard"
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let adjustments = try decoder.decode(AdjustmentSet.self, from: data)
            
            saveToUndoStack()
            currentProject.updateGlobalAdjustments(adjustments)
            processingStatus = "Adjustments pasted from clipboard"
        } catch {
            processingStatus = "Failed to paste adjustments"
        }
    }
    
    func undo() {
        guard let lastAdjustments = undoStack.popLast() else { return }
        
        redoStack.append(currentProject.globalAdjustments.copy())
        currentProject.updateGlobalAdjustments(lastAdjustments)
        
        processingStatus = "Undid last action"
    }
    
    func redo() {
        guard let nextAdjustments = redoStack.popLast() else { return }
        
        undoStack.append(currentProject.globalAdjustments.copy())
        currentProject.updateGlobalAdjustments(nextAdjustments)
        
        processingStatus = "Redid last action"
    }
    
    private func saveToUndoStack() {
        undoStack.append(currentProject.globalAdjustments.copy())
        
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
        
        redoStack.removeAll()
    }
    
    func toggleLivePreview() {
        isLivePreviewEnabled.toggle()
        
        if isLivePreviewEnabled {
            updatePreviewForCurrentFrame()
        }
        
        processingStatus = isLivePreviewEnabled ? "Live preview enabled" : "Live preview disabled"
    }
    
    func updatePreviewQuality(_ quality: PreviewQuality) {
        previewQuality = quality
        updatePreviewForCurrentFrame()
        processingStatus = "Preview quality set to \(quality.rawValue)"
    }
    
    func processAllFrames() async {
        let allFrames = currentProject.frames
        let totalFrames = allFrames.count
        
        guard totalFrames > 0 else { return }
        
        isProcessingFrame = true
        frameProcessingProgress = 0.0
        
        for (index, frame) in allFrames.enumerated() {
            guard let thumbnail = frame.thumbnail,
                  let ciImage = CIImage(image: thumbnail) else {
                continue
            }
            
            let processedImage = imageProcessor.processImageSync(ciImage, adjustments: frame.adjustments)
            
            var updatedFrame = frame
            updatedFrame.setProcessedImage(processedImage)
            
            if let projectIndex = currentProject.frames.firstIndex(where: { $0.id == frame.id }) {
                currentProject.frames[projectIndex] = updatedFrame
            }
            
            await MainActor.run {
                frameProcessingProgress = Double(index + 1) / Double(totalFrames)
                processingStatus = "Processing frame \(index + 1) of \(totalFrames)"
            }
            
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        isProcessingFrame = false
        processingStatus = "All frames processed"
    }
    
    private func areAdjustmentsDefault(_ adjustments: AdjustmentSet) -> Bool {
        let defaultAdjustments = AdjustmentSet()
        
        return adjustments.exposure == defaultAdjustments.exposure &&
               adjustments.highlights == defaultAdjustments.highlights &&
               adjustments.shadows == defaultAdjustments.shadows &&
               adjustments.contrast == defaultAdjustments.contrast &&
               adjustments.brightness == defaultAdjustments.brightness &&
               adjustments.blackPoint == defaultAdjustments.blackPoint &&
               adjustments.saturation == defaultAdjustments.saturation &&
               adjustments.vibrancy == defaultAdjustments.vibrancy &&
               adjustments.temperature == defaultAdjustments.temperature &&
               adjustments.tint == defaultAdjustments.tint &&
               adjustments.hue == defaultAdjustments.hue &&
               adjustments.sharpness == defaultAdjustments.sharpness &&
               adjustments.definition == defaultAdjustments.definition &&
               adjustments.noiseReduction == defaultAdjustments.noiseReduction &&
               adjustments.vignette == defaultAdjustments.vignette &&
               adjustments.grain == defaultAdjustments.grain
    }
}

enum PreviewQuality: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case ultra = "Ultra"
    
    var scale: CGFloat {
        switch self {
        case .low: return 0.25
        case .medium: return 0.5
        case .high: return 0.75
        case .ultra: return 1.0
        }
    }
}