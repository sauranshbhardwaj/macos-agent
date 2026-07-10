import SwiftUI

enum CommandCenterDestination: String, CaseIterable, Identifiable {
    case tasks
    case insights
    case routines
    case workspaces
    case settings

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .tasks:
            return "checklist"
        case .insights:
            return "chart.bar.xaxis"
        case .routines:
            return "repeat"
        case .workspaces:
            return "rectangle.3.group"
        case .settings:
            return "gearshape"
        }
    }
}

struct CommandCenterView: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var selection: CommandCenterDestination = .tasks

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(SonnyTheme.border)
                .frame(width: 1)

            destinationContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(SonnyTheme.ink)
        .foregroundStyle(SonnyTheme.text)
        .tint(SonnyTheme.accent)
        .onAppear {
            viewModel.refreshPermissions()
            viewModel.refreshSavedItems()
            viewModel.refreshClipboardHistoryNotice()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SonnyTheme.accent.opacity(0.16))
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SonnyTheme.accent.opacity(0.42), lineWidth: 1)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(SonnyTheme.accent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Sonny")
                        .font(SonnyType.panelTitle)
                        .foregroundStyle(SonnyTheme.text)
                    Text("Command Center")
                        .font(SonnyType.micro)
                        .foregroundStyle(SonnyTheme.muted)
                }
            }

            VStack(spacing: 5) {
                ForEach(CommandCenterDestination.allCases) { destination in
                    sidebarButton(destination)
                }
            }

            Spacer()

            Text("Local-first shell")
                .font(SonnyType.micro)
                .foregroundStyle(SonnyTheme.muted)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: 226)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.090, green: 0.084, blue: 0.084))
    }

    private func sidebarButton(_ destination: CommandCenterDestination) -> some View {
        Button {
            selection = destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(destination.title)
                    .font(SonnyType.body)
                Spacer(minLength: 8)
                if destination == .tasks, viewModel.activeTaskCount > 0 {
                    Text("\(viewModel.activeTaskCount)")
                        .font(SonnyType.micro)
                        .foregroundStyle(SonnyTheme.ink)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(SonnyTheme.accent)
                        .clipShape(Capsule())
                        .accessibilityLabel("One active task")
                }
            }
            .foregroundStyle(isSelected(destination) ? SonnyTheme.text : SonnyTheme.muted)
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected(destination) ? SonnyTheme.surfaceRaised : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected(destination) ? SonnyTheme.border : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
    }

    private func isSelected(_ destination: CommandCenterDestination) -> Bool {
        selection == destination
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch selection {
        case .tasks:
            TasksFoundationView(viewModel: viewModel)
        case .insights:
            CommandCenterPlaceholderView(
                title: "Insights",
                systemImage: CommandCenterDestination.insights.systemImage,
                message: "Current-task usage will be wired here in Checkpoint 4."
            )
        case .routines:
            CommandCenterPlaceholderView(
                title: "Routines",
                systemImage: CommandCenterDestination.routines.systemImage,
                message: "Saved routines will be wired here in Checkpoint 2."
            )
        case .workspaces:
            CommandCenterPlaceholderView(
                title: "Workspaces",
                systemImage: CommandCenterDestination.workspaces.systemImage,
                message: "Saved workspaces will be wired here in Checkpoint 2."
            )
        case .settings:
            SettingsFoundationView()
        }
    }
}

private struct TasksFoundationView: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                CommandCenterPageHeader(
                    title: "Tasks",
                    subtitle: "Your current Sonny task, live across both surfaces."
                )

                if viewModel.hasTaskActivity {
                    AgentTaskActivityView(viewModel: viewModel, showsStartupWhenEmpty: false)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No active task", systemImage: "checkmark.circle")
                            .font(SonnyType.bodyEmphasis)
                            .foregroundStyle(SonnyTheme.text)
                        Text("Start a command below or from the menu-bar cockpit. The same task will appear here immediately.")
                            .font(SonnyType.body)
                            .foregroundStyle(SonnyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Persistent task history is planned for a future update.")
                            .font(SonnyType.micro)
                            .foregroundStyle(SonnyTheme.muted)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SonnyTheme.surfaceRaised.opacity(0.46))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SonnyTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(SonnyTheme.border)
                .frame(height: 1)

            AgentCommandComposerView(viewModel: viewModel, autoFocus: false)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(Color(red: 0.102, green: 0.095, blue: 0.092))
        }
        .background(SonnyTheme.ink)
    }
}

private struct CommandCenterPlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            CommandCenterPageHeader(title: title, subtitle: "The shared product shell is ready for this section.")

            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(SonnyTheme.accent)
                Text(message)
                    .font(SonnyType.body)
                    .foregroundStyle(SonnyTheme.muted)
            }
            .padding(18)
            .frame(maxWidth: 520, alignment: .leading)
            .background(SonnyTheme.surfaceRaised.opacity(0.42))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SonnyTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SonnyTheme.ink)
    }
}

private struct CommandCenterPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(SonnyType.brand)
                .foregroundStyle(SonnyTheme.text)
            Text(subtitle)
                .font(SonnyType.body)
                .foregroundStyle(SonnyTheme.muted)
        }
    }
}

private struct SettingsFoundationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            CommandCenterPageHeader(
                title: "Settings",
                subtitle: "Preferences, privacy, and permissions will live here."
            )

            VStack(spacing: 0) {
                deferredRow(
                    title: "Preferences",
                    detail: "Clipboard history and command preferences",
                    systemImage: "switch.2"
                )
                Rectangle()
                    .fill(SonnyTheme.border)
                    .frame(height: 1)
                deferredRow(
                    title: "Privacy & Permissions",
                    detail: "Permission readiness and local-data controls",
                    systemImage: "hand.raised"
                )
            }
            .frame(maxWidth: 620)
            .background(SonnyTheme.surfaceRaised.opacity(0.34))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SonnyTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Real preferences and privacy controls will be wired in Checkpoint 3.")
                .font(SonnyType.micro)
                .foregroundStyle(SonnyTheme.muted)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SonnyTheme.ink)
    }

    private func deferredRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SonnyTheme.muted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SonnyType.bodyEmphasis)
                    .foregroundStyle(SonnyTheme.text.opacity(0.74))
                Text(detail)
                    .font(SonnyType.micro)
                    .foregroundStyle(SonnyTheme.muted)
            }
            Spacer()
            Text("Checkpoint 3")
                .font(SonnyType.micro)
                .foregroundStyle(SonnyTheme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    Capsule()
                        .stroke(SonnyTheme.border, lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Available in a later checkpoint")
    }
}
