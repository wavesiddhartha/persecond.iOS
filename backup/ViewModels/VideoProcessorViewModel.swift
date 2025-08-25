import Foundation
import AVFoundation
import Combine
import UIKit

@MainActor
class VideoProcessorViewModel: ObservableObject {
    
    @Published var currentProject: VideoProject?
    @Published var recentProjects: [VideoProject] = []
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0.0
    @Published var processingStatus: String = ""
    @Published var errorMessage: String?
    
    private let frameExtractor = VideoFrameExtractor()
    private let projectsStorageKey = "PerSecondProjects"
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadRecentProjects()
        setupObservers()
    }
    
    private func setupObservers() {
        frameExtractor.$isExtracting
            .receive(on: DispatchQueue.main)
            .assign(to: \.isProcessing, on: self)
            .store(in: &cancellables)
        
        frameExtractor.$extractionProgress
            .receive(on: DispatchQueue.main)
            .assign(to: \.processingProgress, on: self)
            .store(in: &cancellables)
    }
    
    func createNewProject() {
        let project = VideoProject()
        currentProject = project
        processingStatus = "Ready to import video"
    }
    
    func loadProject(_ project: VideoProject) {
        currentProject = project
        processingStatus = "Project loaded"
    }
    
    func importVideo(from url: URL) async throws {
        guard let project = currentProject else {
            throw VideoProcessorError.noActiveProject
        }
        
        processingStatus = "Importing video..."
        
        let asset = AVAsset(url: url)
        
        await MainActor.run {
            project.originalVideoURL = url
            project.asset = asset
            project.duration = asset.duration
            project.name = url.deletingPathExtension().lastPathComponent
        }
        
        processingStatus = "Extracting frames..."
        
        do {
            let frames = try await frameExtractor.extractFrames(from: asset, maxFrames: 120)
            
            await MainActor.run {
                project.addFrames(frames)
                processingStatus = "Import complete"
                saveProject(project)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to extract frames: \(error.localizedDescription)"
                processingStatus = "Import failed"
            }
            throw error
        }
    }
    
    func extractFramesInRange(_ range: ClosedRange<Double>, maxFrames: Int = 120) async throws {
        guard let project = currentProject,
              let asset = project.asset else {
            throw VideoProcessorError.noActiveProject
        }
        
        processingStatus = "Extracting frames in selected range..."
        
        do {
            let frames = try await frameExtractor.extractFrames(from: asset, in: range, maxFrames: maxFrames)
            
            await MainActor.run {
                project.frames.removeAll()
                project.addFrames(frames)
                project.updateSelectedRange(range)
                processingStatus = "Frames extracted successfully"
                saveProject(project)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to extract frames in range: \(error.localizedDescription)"
                processingStatus = "Extraction failed"
            }
            throw error
        }
    }
    
    func saveProject(_ project: VideoProject) {
        
        if let index = recentProjects.firstIndex(where: { $0.id == project.id }) {
            recentProjects[index] = project
        } else {
            recentProjects.insert(project, at: 0)
        }
        
        
        if recentProjects.count > 10 {
            recentProjects = Array(recentProjects.prefix(10))
        }
        
        saveRecentProjects()
        processingStatus = "Project saved"
    }
    
    func deleteProject(_ project: VideoProject) {
        recentProjects.removeAll { $0.id == project.id }
        
        if currentProject?.id == project.id {
            currentProject = nil
        }
        
        saveRecentProjects()
    }
    
    func duplicateProject(_ project: VideoProject) -> VideoProject {
        let duplicate = VideoProject()
        duplicate.name = project.name + " Copy"
        duplicate.originalVideoURL = project.originalVideoURL
        duplicate.asset = project.asset
        duplicate.duration = project.duration
        duplicate.frameRate = project.frameRate
        duplicate.selectedRange = project.selectedRange
        duplicate.frames = project.frames.map { frame in
            var frameCopy = frame
            frameCopy.adjustments = frame.adjustments.copy()
            return frameCopy
        }
        duplicate.globalAdjustments = project.globalAdjustments.copy()
        
        recentProjects.insert(duplicate, at: 0)
        saveRecentProjects()
        
        return duplicate
    }
    
    private func loadRecentProjects() {
        guard let data = UserDefaults.standard.data(forKey: projectsStorageKey) else { return }
        
        do {
            let decoder = JSONDecoder()
            recentProjects = try decoder.decode([VideoProject].self, from: data)
        } catch {
            print("Failed to load recent projects: \(error)")
            recentProjects = []
        }
    }
    
    private func saveRecentProjects() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(recentProjects)
            UserDefaults.standard.set(data, forKey: projectsStorageKey)
        } catch {
            print("Failed to save recent projects: \(error)")
        }
    }
    
    func generateThumbnail(for project: VideoProject) async -> UIImage? {
        guard let asset = project.asset else { return nil }
        
        do {
            return try await frameExtractor.generateThumbnail(from: asset, size: CGSize(width: 200, height: 200))
        } catch {
            print("Failed to generate thumbnail: \(error)")
            return nil
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
}

enum VideoProcessorError: LocalizedError {
    case noActiveProject
    case invalidVideoURL
    case extractionFailed
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .noActiveProject:
            return "No active project available"
        case .invalidVideoURL:
            return "Invalid video URL provided"
        case .extractionFailed:
            return "Failed to extract frames from video"
        case .exportFailed:
            return "Failed to export processed video"
        }
    }
}