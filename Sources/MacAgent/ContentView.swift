import MacAgentCore
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AgentViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            SetupStatusPanel(viewModel: viewModel)
            commandInput
            controls

            if viewModel.isRunning {
                BusyPanel(logStore: viewModel.logStore)
            }

            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }

            RunDetailsView(viewModel: viewModel, logStore: viewModel.logStore)
        }
        .padding(18)
        .frame(width: 560, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $viewModel.showConfirmation) {
            ConfirmationView(viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("MacAgent")
                    .font(.system(size: 22, weight: .semibold))
                Text("Plan. Validate. Act. Observe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
    }

    private var commandInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Command")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Find the 3 largest files in ~/Desktop and zip them.", text: $viewModel.command, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...5)
                .disabled(viewModel.isRunning)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Toggle("Dry run", isOn: $viewModel.dryRun)
                .toggleStyle(.switch)
                .disabled(viewModel.isRunning)

            Spacer()

            if viewModel.canCancel {
                Button {
                    viewModel.cancelCurrentRun()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            }

            Button {
                viewModel.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .disabled(viewModel.isRunning)

            Button {
                viewModel.start()
            } label: {
                Label(viewModel.primaryButtonTitle, systemImage: viewModel.primaryButtonIcon)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!viewModel.canSubmit)
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct SetupStatusPanel: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.hasAPIKey ? "checkmark.seal" : "key.slash")
                .foregroundStyle(viewModel.hasAPIKey ? .green : .orange)
            Text(viewModel.setupStatus)
                .font(.caption.weight(.medium))
                .foregroundStyle(viewModel.hasAPIKey ? Color.secondary : Color.orange)
            Spacer()
            Text("Whitelist: Desktop, Documents")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RunDetailsView: View {
    @ObservedObject var viewModel: AgentViewModel
    @ObservedObject var logStore: AgentLogStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let plan = viewModel.plan {
                        PlanPanel(plan: plan)
                    }

                    if !viewModel.previews.isEmpty {
                        PreviewPanel(previews: viewModel.previews)
                    }

                    LogPanel(logStore: logStore)

                    if !viewModel.finalSummary.isEmpty {
                        SummaryPanel(summary: viewModel.finalSummary, copy: viewModel.copySummary)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("run-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: logStore.events.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.finalSummary) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("run-bottom", anchor: .bottom)
            }
        }
    }
}

private struct PlanPanel: View {
    let plan: AgentPlan

    var body: some View {
        Panel(title: "Plan", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                Text(plan.summary)
                    .font(.callout.weight(.medium))

                ForEach(plan.steps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Text(step.operation.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 155, alignment: .leading)
                        Text(step.description)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct PreviewPanel: View {
    let previews: [ActionPreview]

    var body: some View {
        Panel(title: "Preview", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(previews) { preview in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preview.title)
                            .font(.callout.weight(.semibold))

                        ForEach(preview.details, id: \.self) { detail in
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForEach(preview.sideEffects, id: \.self) { sideEffect in
                            Label(sideEffect, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

private struct LogPanel: View {
    @ObservedObject var logStore: AgentLogStore

    var body: some View {
        Panel(title: "Log", systemImage: "waveform.path.ecg") {
            if logStore.events.isEmpty {
                Text("Idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(logStore.events) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(event.phase.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(phaseColor(event.phase))
                                .frame(width: 74, alignment: .leading)
                            Text(event.message)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func phaseColor(_ phase: AgentPhase) -> Color {
        switch phase {
        case .plan:
            return .blue
        case .validate:
            return .purple
        case .preview:
            return .teal
        case .confirm:
            return .orange
        case .act:
            return .indigo
        case .observe:
            return .green
        case .summarize:
            return .secondary
        }
    }
}

private struct BusyPanel: View {
    @ObservedObject var logStore: AgentLogStore

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(latestMessage)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var latestMessage: String {
        guard let event = logStore.events.last else {
            return "Working..."
        }
        return "\(event.phase.rawValue): \(event.message)"
    }
}

private struct SummaryPanel: View {
    let summary: String
    let copy: () -> Void

    var body: some View {
        Panel(title: "Summary", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: copy) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct Panel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ConfirmationView: View {
    @ObservedObject var viewModel: AgentViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Confirm", systemImage: "lock.open")
                .font(.title2.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.confirmationItems, id: \.self) { item in
                        Label(item, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button {
                    viewModel.executeConfirmed()
                } label: {
                    Label("Execute", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunning)
            }
        }
        .padding(18)
        .frame(width: 460, height: 320)
    }
}
