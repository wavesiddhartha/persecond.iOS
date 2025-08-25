import SwiftUI

struct AdjustmentPanelView: View {
    @ObservedObject var project: VideoProject
    @ObservedObject var imageProcessor: LiveImageProcessor
    
    @State private var selectedCategory: AdjustmentCategory = .light
    @State private var showingAutoAdjust: Bool = false
    @State private var showingPresets: Bool = false
    @State private var isAdjusting: Bool = false
    
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 0) {
            
            categoryTabs
            
            Divider()
            
            
            ScrollView {
                LazyVStack(spacing: 16) {
                    switch selectedCategory {
                    case .light:
                        lightAdjustments
                    case .color:
                        colorAdjustments
                    case .detail:
                        detailAdjustments
                    }
                }
                .padding()
            }
            .frame(maxHeight: 400)
            
            Divider()
            
            
            controlButtons
        }
        .background(.ultraThinMaterial)
        .cornerRadius(16, corners: [.topLeading, .topTrailing])
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -2)
    }
    
    @ViewBuilder
    private var categoryTabs: some View {
        HStack(spacing: 0) {
            ForEach(AdjustmentCategory.allCases, id: \.self) { category in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = category
                    }
                    hapticFeedback.impactOccurred(intensity: 0.5)
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: category.systemImage)
                            .font(.title2)
                            .foregroundColor(selectedCategory == category ? .accentColor : .secondary)
                        
                        Text(category.title)
                            .font(.caption)
                            .foregroundColor(selectedCategory == category ? .accentColor : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selectedCategory == category ?
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.thinMaterial)
                        : nil
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var lightAdjustments: some View {
        AdjustmentSliderGroup(
            title: "Exposure",
            systemImage: "sun.max",
            sliders: [
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.exposure,
                    range: -2.0...2.0,
                    step: 0.1,
                    label: "Exposure",
                    systemImage: "sun.max",
                    unit: "EV",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                ),
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.highlights,
                    range: -100...100,
                    step: 1.0,
                    label: "Highlights",
                    systemImage: "sun.max.fill",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                ),
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.shadows,
                    range: -100...100,
                    step: 1.0,
                    label: "Shadows",
                    systemImage: "sun.min.fill",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                )
            ]
        )
        
        AdjustmentSliderGroup(
            title: "Tone",
            systemImage: "circle.lefthalf.filled",
            sliders: [
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.contrast,
                    range: -100...100,
                    step: 1.0,
                    label: "Contrast",
                    systemImage: "circle.lefthalf.filled",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                ),
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.brightness,
                    range: -100...100,
                    step: 1.0,
                    label: "Brightness",
                    systemImage: "brightness",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                ),
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.blackPoint,
                    range: -100...100,
                    step: 1.0,
                    label: "Black Point",
                    systemImage: "circle.fill",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                )
            ]
        )
    }
    
    @ViewBuilder
    private var colorAdjustments: some View {
        AdjustmentSliderGroup(
            title: "Saturation",
            systemImage: "paintbrush.pointed",
            sliders: [
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.saturation,
                    range: -100...100,
                    step: 1.0,
                    label: "Saturation",
                    systemImage: "paintbrush.pointed",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                ),
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.vibrancy,
                    range: -100...100,
                    step: 1.0,
                    label: "Vibrancy",
                    systemImage: "paintbrush.pointed.fill",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                )
            ]
        )
        
        AdjustmentSliderGroup(
            title: "White Balance",
            systemImage: "thermometer",
            sliders: [
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.temperature,
                    range: -100...100,
                    step: 1.0,
                    label: "Temperature",
                    systemImage: "thermometer",
                    unit: "K",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                ),
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.tint,
                    range: -100...100,
                    step: 1.0,
                    label: "Tint",
                    systemImage: "drop.fill",
                    unit: "",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                )
            ]
        )
        
        AdjustmentSliderGroup(
            title: "Hue",
            systemImage: "paintpalette",
            sliders: [
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.hue,
                    range: -180...180,
                    step: 1.0,
                    label: "Hue",
                    systemImage: "paintpalette",
                    unit: "°",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                )
            ]
        )
    }
    
    @ViewBuilder
    private var detailAdjustments: some View {
        AdjustmentSliderGroup(
            title: "Sharpening",
            systemImage: "triangle",
            sliders: [
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.sharpness,
                    range: -100...100,
                    step: 1.0,
                    label: "Sharpness",
                    systemImage: "triangle",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                ),
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.definition,
                    range: -100...100,
                    step: 1.0,
                    label: "Definition",
                    systemImage: "diamond",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                )
            ]
        )
        
        AdjustmentSliderGroup(
            title: "Noise & Texture",
            systemImage: "scribble.variable",
            sliders: [
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.noiseReduction,
                    range: 0...100,
                    step: 1.0,
                    label: "Noise Reduction",
                    systemImage: "waveform",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                ),
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.grain,
                    range: 0...100,
                    step: 1.0,
                    label: "Grain",
                    systemImage: "scribble.variable",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                )
            ]
        )
        
        AdjustmentSliderGroup(
            title: "Vignette",
            systemImage: "circle.dotted",
            sliders: [
                AdjustmentSliderConfig(
                    binding: $project.globalAdjustments.vignette,
                    range: -100...100,
                    step: 1.0,
                    label: "Vignette",
                    systemImage: "circle.dotted",
                    unit: "%",
                    onValueChanged: { _ in triggerLiveUpdate() },
                    onEditingChanged: { editing in isAdjusting = editing }
                )
            ]
        )
    }
    
    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 20) {
            
            Button(action: triggerAutoAdjust) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.rays")
                        .font(.title3)
                    Text("Auto")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
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
            .disabled(isAdjusting || showingAutoAdjust)
            
            Spacer()
            
            
            Button(action: resetAllAdjustments) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                    Text("Reset")
                        .font(.headline)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.thinMaterial)
                .cornerRadius(25)
            }
            .disabled(isAdjusting)
            
            
            Button(action: { showingPresets.toggle() }) {
                Image(systemName: "square.stack.3d.up")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .padding(12)
                    .background(Circle().fill(.thinMaterial))
            }
            .disabled(isAdjusting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private func triggerLiveUpdate() {
        if let currentFrame = project.currentFrame,
           let image = CIImage(image: currentFrame.thumbnail ?? UIImage()) {
            imageProcessor.setBaseImage(image)
            imageProcessor.processImageLive(project.globalAdjustments)
        }
    }
    
    private func triggerAutoAdjust() {
        guard let currentFrame = project.currentFrame,
              let image = CIImage(image: currentFrame.thumbnail ?? UIImage()) else { return }
        
        showingAutoAdjust = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let autoAdjustments = imageProcessor.generateAutoAdjustments(for: image)
            
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.5)) {
                    project.updateGlobalAdjustments(autoAdjustments)
                }
                showingAutoAdjust = false
                hapticFeedback.impactOccurred(intensity: 0.8)
            }
        }
    }
    
    private func resetAllAdjustments() {
        withAnimation(.easeInOut(duration: 0.3)) {
            project.globalAdjustments.reset()
        }
        hapticFeedback.impactOccurred(intensity: 0.6)
        triggerLiveUpdate()
    }
}

enum AdjustmentCategory: String, CaseIterable {
    case light = "Light"
    case color = "Color"
    case detail = "Detail"
    
    var title: String {
        return rawValue
    }
    
    var systemImage: String {
        switch self {
        case .light:
            return "sun.max"
        case .color:
            return "paintpalette"
        case .detail:
            return "triangle"
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    @State var project = VideoProject()
    
    return AdjustmentPanelView(
        project: project,
        imageProcessor: LiveImageProcessor(metalDevice: MTLCreateSystemDefaultDevice()!)
    )
}