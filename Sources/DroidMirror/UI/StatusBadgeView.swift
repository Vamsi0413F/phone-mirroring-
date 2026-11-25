import SwiftUI

public struct StatusBadgeView: View {
    public let state: DeviceState
    
    public init(state: DeviceState) {
        self.state = state
    }
    
    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(colorForState)
                .frame(width: 8, height: 8)
            
            Text(state.userFriendlyTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorForState)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(colorForState.opacity(0.12))
        .cornerRadius(6)
    }
    
    private var colorForState: Color {
        switch state {
        case .device:
            return .green
        case .unauthorized:
            return .orange
        case .offline:
            return .secondary
        case .authorizing, .connecting:
            return .blue
        case .unknown:
            return .gray
        }
    }
}
