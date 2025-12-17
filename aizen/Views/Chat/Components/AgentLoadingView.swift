//
//  AgentLoadingView.swift
//  aizen
//
//  Loading view shown when agent session is starting
//

import SwiftUI
import Combine

struct AgentLoadingView: View {
    let agentName: String

    @State private var rotation: Double = 0
    @State private var currentTipIndex: Int = 0
    @State private var tipOpacity: Double = 1.0

    private let tips = [
        "Warming up the neural pathways...",
        "Preparing your coding companion...",
        "Loading context and capabilities...",
        "Tip: Use @ to mention files or folders",
        "Tip: Press ⌘+K to toggle modes",
        "Tip: Drag files into chat to attach them",
        "Tip: Use /help to see available commands",
        "Connecting to the AI backend...",
        "Almost ready to assist you...",
        "Initializing development environment...",
    ]

    private let tipRotationTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated agent icon with spinning ring
            ZStack {
                // Spinning arc
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        agentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(rotation))

                // Icon container
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 72, height: 72)

                // Agent icon
                AgentIconView(agent: agentName, size: 40)
            }

            // Loading text
            VStack(spacing: 8) {
                Text("Starting \(displayName)")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(tips[currentTipIndex])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(tipOpacity)
                    .animation(.easeInOut(duration: 0.3), value: tipOpacity)
                    .frame(height: 20)
            }
            .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startAnimations()
        }
        .onReceive(tipRotationTimer) { _ in
            rotateTip()
        }
    }

    // MARK: - Computed Properties

    private var displayName: String {
        if let meta = AgentRegistry.shared.getMetadata(for: agentName) {
            return meta.name
        }
        return agentName.capitalized
    }

    private var agentColor: Color {
        switch agentName.lowercased() {
        case "claude":
            return Color(red: 0.85, green: 0.55, blue: 0.35)  // Claude orange/tan
        case "gemini":
            return Color(red: 0.4, green: 0.5, blue: 0.9)  // Gemini blue
        case "codex", "openai":
            return Color(red: 0.3, green: 0.75, blue: 0.65)  // OpenAI teal
        case "kimi":
            return Color(red: 0.6, green: 0.4, blue: 0.8)  // Kimi purple
        default:
            return Color.accentColor
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        withAnimation(
            .linear(duration: 1.2)
            .repeatForever(autoreverses: false)
        ) {
            rotation = 360
        }
    }

    private func rotateTip() {
        // Fade out
        withAnimation(.easeOut(duration: 0.2)) {
            tipOpacity = 0
        }

        // Change tip and fade in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            currentTipIndex = (currentTipIndex + 1) % tips.count
            withAnimation(.easeIn(duration: 0.3)) {
                tipOpacity = 1
            }
        }
    }
}

#Preview {
    AgentLoadingView(agentName: "claude")
        .frame(width: 400, height: 500)
}
