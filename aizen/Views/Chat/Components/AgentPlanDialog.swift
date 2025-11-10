//
//  AgentPlanDialog.swift
//  aizen
//
//  Dialog displaying agent plan progress
//

import SwiftUI

struct AgentPlanDialog: View {
    let plan: Plan
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent Plan")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(plan.entries.enumerated()), id: \.offset) { index, entry in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(statusColor(for: entry.status))
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            VStack(alignment: .leading, spacing: 4) {
                                PlanContentView(content: entry.content)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)

                                if let activeForm = entry.activeForm, entry.status == .inProgress {
                                    PlanContentView(content: activeForm)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }

                                Text(statusLabel(for: entry.status))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(statusColor(for: entry.status))
                                    .textCase(.uppercase)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(entry.status == .inProgress ? Color.blue.opacity(0.05) : Color.clear)
                        )

                        if index < plan.entries.count - 1 {
                            Divider()
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 700, height: 500)
        .background(.ultraThinMaterial)
    }

    private func statusColor(for status: PlanEntryStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .cancelled:
            return .red
        }
    }

    private func statusLabel(for status: PlanEntryStatus) -> String {
        switch status {
        case .pending:
            return String(localized: "chat.status.pending")
        case .inProgress:
            return String(localized: "chat.status.inProgress")
        case .completed:
            return String(localized: "chat.status.completed")
        case .cancelled:
            return String(localized: "chat.status.cancelled")
        }
    }
}
