//
//  PlanApprovalDialog.swift
//  aizen
//
//  Dialog for approving/rejecting agent plans
//

import SwiftUI

struct PlanApprovalDialog: View {
    @ObservedObject var session: AgentSession
    let request: RequestPermissionRequest
    @Binding var isPresented: Bool

    private var planContent: String? {
        guard let toolCall = request.toolCall,
              let rawInput = toolCall.rawInput?.value as? [String: Any],
              let plan = rawInput["plan"] as? String else {
            return nil
        }
        return plan
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.clipboard")
                    .font(.title3)
                    .foregroundStyle(.blue)

                Text("Agent Plan")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial)

            Divider()

            // Plan content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Review the agent's proposed plan:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let planContent = planContent {
                        PlanContentView(content: planContent)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .padding(24)
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                if let options = request.options {
                    ForEach(options, id: \.optionId) { option in
                        Button {
                            session.respondToPermission(optionId: option.optionId)
                            isPresented = false
                        } label: {
                            HStack(spacing: 6) {
                                if option.kind.contains("allow") {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                } else if option.kind.contains("reject") {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                }
                                Text(option.name)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(buttonForeground(for: option))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background {
                                buttonBackground(for: option)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
        .frame(width: 600, height: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    private func buttonForeground(for option: PermissionOption) -> Color {
        if option.kind.contains("allow") {
            return .white
        } else if option.kind.contains("reject") {
            return .white
        } else {
            return .primary
        }
    }

    private func buttonBackground(for option: PermissionOption) -> Color {
        if option.kind == "allow_always" {
            return .green
        } else if option.kind.contains("allow") {
            return .blue
        } else if option.kind.contains("reject") {
            return .red
        } else {
            return .secondary.opacity(0.2)
        }
    }
}
