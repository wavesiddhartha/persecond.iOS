import SwiftUI
import UIKit

struct LiveSliderView: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let label: String
    let systemImage: String
    let unit: String?
    let isEnabled: Bool
    let onValueChanged: ((Double) -> Void)?
    let onEditingChanged: ((Bool) -> Void)?
    
    @State private var isDragging: Bool = false
    @State private var tempValue: Double
    @State private var lastHapticValue: Double = 0
    
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private let selectionHaptic = UISelectionFeedbackGenerator()
    
    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        label: String,
        systemImage: String,
        unit: String? = nil,
        isEnabled: Bool = true,
        onValueChanged: ((Double) -> Void)? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.label = label
        self.systemImage = systemImage
        self.unit = unit
        self.isEnabled = isEnabled
        self.onValueChanged = onValueChanged
        self.onEditingChanged = onEditingChanged
        self._tempValue = State(initialValue: value.wrappedValue)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            
            HStack {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                    .frame(width: 16)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                
                Spacer()
                
                if isDragging {
                    Text(formattedValue(tempValue))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.ultraThinMaterial)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            
            
            ZStack(alignment: .leading) {
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(isEnabled ? Color.gray.opacity(0.3) : Color.gray.opacity(0.1))
                    .frame(height: 4)
                
                
                let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                let centerPosition = 0.5
                let adjustmentWidth = abs(normalizedValue - centerPosition)
                let adjustmentOffset = min(normalizedValue, centerPosition)
                
                if value != 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: value > 0 ? [.blue.opacity(0.3), .blue] : [.orange, .orange.opacity(0.3)],
                                startPoint: value > 0 ? .leading : .trailing,
                                endPoint: value > 0 ? .trailing : .leading
                            )
                        )
                        .frame(height: 4)
                        .scaleEffect(x: adjustmentWidth * 2, y: 1, anchor: value > 0 ? .leading : .trailing)
                        .offset(x: value > 0 ? 0 : 0)
                        .animation(.easeOut(duration: 0.1), value: value)
                }
                
                
                GeometryReader { geometry in
                    Circle()
                        .fill(.white)
                        .frame(width: isDragging ? 28 : 24, height: isDragging ? 28 : 24)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .scaleEffect(isDragging ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
                        .position(
                            x: geometry.size.width * normalizedValue,
                            y: geometry.size.height / 2
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { dragValue in
                                    if !isDragging {
                                        isDragging = true
                                        onEditingChanged?(true)
                                        hapticFeedback.prepare()
                                    }
                                    
                                    let newValue = calculateValue(from: dragValue.location.x, in: geometry.size.width)
                                    updateValue(newValue)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    onEditingChanged?(false)
                                    value = tempValue
                                }
                        )
                }
                .frame(height: 32)
            }
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .onAppear {
            tempValue = value
            hapticFeedback.prepare()
        }
        .onChange(of: value) { oldValue, newValue in
            if !isDragging {
                withAnimation(.easeInOut(duration: 0.2)) {
                    tempValue = newValue
                }
            }
        }
    }
    
    private func calculateValue(from position: CGFloat, in width: CGFloat) -> Double {
        let normalizedPosition = max(0, min(1, position / width))
        var newValue = range.lowerBound + normalizedPosition * (range.upperBound - range.lowerBound)
        
        if let step = step {
            newValue = round(newValue / step) * step
        }
        
        return max(range.lowerBound, min(range.upperBound, newValue))
    }
    
    private func updateValue(_ newValue: Double) {
        let clampedValue = max(range.lowerBound, min(range.upperBound, newValue))
        
        if abs(clampedValue - tempValue) > 0.01 {
            tempValue = clampedValue
            
            
            triggerHapticFeedback(for: clampedValue)
            
            
            onValueChanged?(clampedValue)
        }
    }
    
    private func triggerHapticFeedback(for value: Double) {
        let threshold = (range.upperBound - range.lowerBound) * 0.05
        
        
        if abs(value) < threshold && abs(lastHapticValue) >= threshold {
            selectionHaptic.selectionChanged()
        }
        
        else if abs(value - range.lowerBound) < threshold || abs(value - range.upperBound) < threshold {
            if abs(value - lastHapticValue) > threshold {
                hapticFeedback.impactOccurred(intensity: 0.7)
            }
        }
        
        else if abs(value - lastHapticValue) > threshold * 2 {
            hapticFeedback.impactOccurred(intensity: 0.3)
        }
        
        lastHapticValue = value
    }
    
    private func formattedValue(_ value: Double) -> String {
        if let unit = unit {
            return String(format: "%.1f%@", value, unit)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

struct AdjustmentSliderGroup: View {
    let title: String
    let systemImage: String
    let sliders: [AdjustmentSliderConfig]
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 24)
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.3), value: isExpanded)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(sliders, id: \.id) { config in
                        LiveSliderView(
                            value: config.binding,
                            in: config.range,
                            step: config.step,
                            label: config.label,
                            systemImage: config.systemImage,
                            unit: config.unit,
                            isEnabled: config.isEnabled,
                            onValueChanged: config.onValueChanged,
                            onEditingChanged: config.onEditingChanged
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .slide))
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

struct AdjustmentSliderConfig: Identifiable {
    let id = UUID()
    let binding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double?
    let label: String
    let systemImage: String
    let unit: String?
    let isEnabled: Bool
    let onValueChanged: ((Double) -> Void)?
    let onEditingChanged: ((Bool) -> Void)?
    
    init(
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        label: String,
        systemImage: String,
        unit: String? = nil,
        isEnabled: Bool = true,
        onValueChanged: ((Double) -> Void)? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self.binding = binding
        self.range = range
        self.step = step
        self.label = label
        self.systemImage = systemImage
        self.unit = unit
        self.isEnabled = isEnabled
        self.onValueChanged = onValueChanged
        self.onEditingChanged = onEditingChanged
    }
}

#Preview {
    @State var exposure: Double = 0.0
    @State var contrast: Double = 25.0
    @State var brightness: Double = -10.0
    
    return VStack(spacing: 20) {
        LiveSliderView(
            value: $exposure,
            in: -2.0...2.0,
            label: "Exposure",
            systemImage: "sun.max",
            unit: "EV",
            onValueChanged: { value in
                print("Exposure: \(value)")
            }
        )
        
        LiveSliderView(
            value: $contrast,
            in: -100...100,
            label: "Contrast",
            systemImage: "circle.lefthalf.filled",
            unit: "%",
            onValueChanged: { value in
                print("Contrast: \(value)")
            }
        )
        
        LiveSliderView(
            value: $brightness,
            in: -100...100,
            label: "Brightness",
            systemImage: "brightness",
            unit: "%",
            onValueChanged: { value in
                print("Brightness: \(value)")
            }
        )
    }
    .padding()
}