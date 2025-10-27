//
//  AgentIconView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 27.10.25.
//

import SwiftUI

/// Shared agent icon view builder
struct AgentIconView: View {
    let agent: String
    let size: CGFloat

    var body: some View {
        switch agent.lowercased() {
        case "claude":
            Image("claude")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case "gemini":
            Image("gemini")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case "codex", "openai":
            Image("openai")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        default:
            Image(systemName: "brain.head.profile")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }
}
