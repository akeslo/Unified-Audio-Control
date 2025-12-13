import SwiftUI

struct HUDView: View {
    let type: HUDType
    let value: Float
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
            
            ProgressView(value: value)
                .progressViewStyle(LinearProgressViewStyle())
                .tint(.secondary)
                .frame(width: 160)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        .frame(width: 240, height: 50)
    }
    
    var iconName: String {
        switch type {
        case .volume:
            if value <= 0 { return "speaker.slash" }
            if value < 0.33 { return "speaker.wave.1" }
            if value < 0.66 { return "speaker.wave.2" }
            return "speaker.wave.3"
        case .brightness:
            return "sun.max"
        }
    }
}

enum HUDType {
    case volume
    case brightness
}
