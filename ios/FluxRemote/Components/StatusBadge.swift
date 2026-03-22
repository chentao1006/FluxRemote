import SwiftUI

struct StatusBadge: View {
    let status: String
    var showLabel: Bool = false
    var size: CGFloat = 8
    
    var color: Color {
        let s = status.lowercased()
        if s == "running" || s == "enabled" || s == "online" || s == "active" || s == "loaded" {
            return .green
        } else if s == "stopped" || s == "disabled" || s == "offline" || s == "inactive" || s == "unloaded" || s == "exited" {
            return .red
        } else if s == "restarting" || s == "loading" {
            return .orange
        }
        return .gray
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .foregroundStyle(color)
                .font(.system(size: size))
            
            if showLabel {
                Text(status.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }
}
