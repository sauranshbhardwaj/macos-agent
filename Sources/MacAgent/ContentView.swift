import MacAgentCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AgentViewModel
    @FocusState private var commandFocused: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            SonnyTheme.glassShade
            LinearGradient(
                colors: [
                    SonnyTheme.accent.opacity(0.08),
                    Color.clear,
                    SonnyTheme.cyan.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 16) {
                header
                if viewModel.showPermissionPanel {
                    SystemStatusPanel(viewModel: viewModel)
                }
                commandInput
                controls
                SavedItemsPanel(viewModel: viewModel)

                if viewModel.isPreparingVoiceRecording || viewModel.isRecordingVoice || viewModel.isTranscribingVoice {
                    VoiceStatusPanel(viewModel: viewModel)
                }

                if viewModel.isRunning {
                    BusyPanel(logStore: viewModel.logStore)
                }

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                if let question = viewModel.clarificationQuestion {
                    ClarificationPanel(viewModel: viewModel, question: question)
                }

                RunDetailsView(viewModel: viewModel, logStore: viewModel.logStore)
            }
            .padding(20)
        }
        .frame(width: 600, height: 740)
        .background(.clear)
        .foregroundStyle(SonnyTheme.text)
        .onAppear {
            commandFocused = true
            viewModel.refreshPermissions()
            viewModel.refreshSavedItems()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SonnyMark()

            VStack(alignment: .leading, spacing: 1) {
                Text("Sonny")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(SonnyTheme.text)
                Text("Ask. Check. Done.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SonnyTheme.muted)
            }
            Spacer()
            Button {
                viewModel.togglePermissionPanel()
            } label: {
                Label("Status", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(SonnyButtonStyle(tone: .secondary))
            .help("Show model, voice, and permission status")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(SonnyIconButtonStyle())
            .help("Quit")
        }
    }

    private var commandInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask Sonny")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SonnyTheme.muted)
            TextField("Open Safari, zip files, convert docs...", text: $viewModel.command)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(SonnyTheme.input)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(commandFocused ? SonnyTheme.accent.opacity(0.72) : SonnyTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(viewModel.isRunning)
                .focused($commandFocused)
                .submitLabel(.go)
                .onSubmit {
                    viewModel.start()
                }

            if !viewModel.voiceTranscript.isEmpty {
                Label("Voice command received", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(SonnyTheme.muted)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Toggle("Dry run", isOn: $viewModel.dryRun)
                .toggleStyle(.switch)
                .disabled(viewModel.isRunning)

            Button {
                viewModel.toggleVoiceRecording()
            } label: {
                Label(viewModel.voiceButtonTitle, systemImage: viewModel.voiceButtonIcon)
            }
            .disabled(!viewModel.canUseVoice && !viewModel.isRecordingVoice)
            .buttonStyle(SonnyButtonStyle(tone: viewModel.isRecordingVoice ? .danger : .secondary))
            .help("Click to speak, or hold Control-Option-Space")

            HotKeyHint(title: viewModel.voiceHotKeyReady ? "Ctrl-Opt-Space" : "Hotkey unavailable")

            Spacer()

            if viewModel.canCancel {
                Button {
                    viewModel.cancelCurrentRun()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(SonnyButtonStyle(tone: .secondary))
            }

            Button {
                viewModel.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .disabled(viewModel.isRunning)
            .buttonStyle(SonnyButtonStyle(tone: .secondary))

            Button {
                viewModel.start()
            } label: {
                Label(viewModel.primaryButtonTitle, systemImage: viewModel.primaryButtonIcon)
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!viewModel.canSubmit)
            .buttonStyle(SonnyButtonStyle(tone: .primary))
        }
    }
}

private struct SonnyMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            SonnyTheme.accent.opacity(0.26),
                            SonnyTheme.cyan.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SonnyTheme.accent.opacity(0.38), lineWidth: 1)
                )
            Image(systemName: "wand.and.stars.inverse")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SonnyTheme.accent)
        }
        .frame(width: 40, height: 40)
    }
}

private struct HotKeyHint: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "keyboard")
            .font(.caption2.weight(.medium))
            .foregroundStyle(SonnyTheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(SonnyTheme.surfaceRaised.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .lineLimit(1)
    }
}

private struct SystemStatusPanel: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        Panel(title: "System", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    StatusChip(
                        title: viewModel.hasAPIKey ? "OpenAI ready" : "Needs key",
                        systemImage: viewModel.hasAPIKey ? "checkmark.seal" : "key.slash",
                        tone: viewModel.hasAPIKey ? .ready : .warning
                    )
                    StatusChip(title: viewModel.modelName, systemImage: "brain", tone: .neutral)
                    StatusChip(title: viewModel.transcriptionModelName, systemImage: "waveform", tone: .neutral)
                    StatusChip(
                        title: viewModel.voiceHotKeyReady ? viewModel.voiceHotKeyStatus : "Hotkey unavailable",
                        systemImage: "keyboard",
                        tone: viewModel.voiceHotKeyReady ? .neutral : .warning
                    )
                }

                PermissionReadinessRows(items: viewModel.permissionItems)
            }
        }
    }
}

private struct PermissionReadinessRows: View {
    let items: [PermissionReadinessItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: item.state))
                        .font(.caption)
                        .foregroundStyle(color(for: item.state))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SonnyTheme.text)
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(SonnyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func icon(for state: PermissionReadinessState) -> String {
        switch state {
        case .ready:
            return "checkmark.circle"
        case .needsAction:
            return "exclamationmark.triangle"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func color(for state: PermissionReadinessState) -> Color {
        switch state {
        case .ready:
            return SonnyTheme.accent
        case .needsAction:
            return SonnyTheme.warning
        case .unknown:
            return SonnyTheme.muted
        }
    }
}

private struct StatusChip: View {
    let title: String
    let systemImage: String
    let tone: Tone

    enum Tone {
        case ready
        case warning
        case neutral
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .lineLimit(1)
    }

    private var foreground: Color {
        switch tone {
        case .ready:
            return SonnyTheme.accent
        case .warning:
            return SonnyTheme.warning
        case .neutral:
            return SonnyTheme.muted
        }
    }

    private var background: Color {
        switch tone {
        case .ready:
            return SonnyTheme.accent.opacity(0.12)
        case .warning:
            return SonnyTheme.warning.opacity(0.14)
        case .neutral:
            return SonnyTheme.surfaceRaised
        }
    }
}

private struct SavedItemsPanel: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        if !viewModel.savedRoutines.isEmpty || !viewModel.savedWorkspaces.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                SavedColumn(
                    title: "Routines",
                    systemImage: "repeat",
                    emptyLabel: "No routines",
                    items: viewModel.savedRoutines.map { routine in
                        SavedItem(
                            title: routine.name,
                            subtitle: "\(routine.steps.count) step\(routine.steps.count == 1 ? "" : "s")",
                            details: routine.steps.prefix(4).map(routineStepLabel),
                            actionTitle: "Run",
                            actionIcon: "play",
                            action: { viewModel.runRoutineWidget(routine) }
                        )
                    }
                )

                SavedColumn(
                    title: "Workspaces",
                    systemImage: "rectangle.3.group",
                    emptyLabel: "No workspaces",
                    items: viewModel.savedWorkspaces.map { workspace in
                        let appCount = workspace.apps.count
                        let urlCount = workspace.urls.count
                        return SavedItem(
                            title: workspace.name,
                            subtitle: "\(appCount) app\(appCount == 1 ? "" : "s"), \(urlCount) URL\(urlCount == 1 ? "" : "s")",
                            details: workspaceDetails(workspace),
                            actionTitle: "Open",
                            actionIcon: "arrow.up.right",
                            action: { viewModel.openWorkspaceWidget(workspace) }
                        )
                    }
                )
            }
        }
    }

    private func routineStepLabel(_ step: AgentStep) -> String {
        switch step.operation {
        case .openApp:
            return "Open \(step.appName ?? "app")"
        case .openURL:
            return "Open \(step.targetURL ?? "URL")"
        case .playMedia:
            return "Open \(step.mediaTitle ?? "music")"
        case .scanSelectLargestFiles:
            return "Find largest files"
        case .createZip:
            return "Create zip"
        case .scanDocx:
            return "Find DOCX files"
        case .convertDocxToPDF:
            return "Convert DOCX to PDF"
        case .openHackerNews:
            return "Open Hacker News"
        case .fetchHNHeadlines:
            return "Fetch HN headlines"
        case .writeMarkdown:
            return "Write Markdown"
        case .getFinderSelection:
            return "Read Finder selection"
        case .revealInFinder:
            return "Reveal in Finder"
        case .showPermissionReadiness:
            return "Check status"
        case .saveRoutine:
            return "Save routine"
        case .runRoutine:
            return "Run routine"
        case .createWorkspace:
            return "Create workspace"
        case .openWorkspace:
            return "Open workspace"
        case .clarify:
            return "Ask clarification"
        case .unsupported:
            return "Unsupported step"
        }
    }

    private func workspaceDetails(_ workspace: StoredWorkspace) -> [String] {
        let apps = workspace.apps.isEmpty ? [] : ["Apps: \(workspace.apps.joined(separator: ", "))"]
        let urls = workspace.urls.isEmpty ? [] : ["URLs: \(workspace.urls.joined(separator: ", "))"]
        return apps + urls
    }
}

private struct SavedItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let details: [String]
    let actionTitle: String
    let actionIcon: String
    let action: () -> Void
}

private struct SavedColumn: View {
    let title: String
    let systemImage: String
    let emptyLabel: String
    let items: [SavedItem]

    var body: some View {
        Panel(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 8) {
                if items.isEmpty {
                    Text(emptyLabel)
                        .font(.caption)
                        .foregroundStyle(SonnyTheme.muted)
                } else {
                    ForEach(items.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(SonnyTheme.text)
                                        .lineLimit(1)
                                    Text(item.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(SonnyTheme.muted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button(action: item.action) {
                                    Label(item.actionTitle, systemImage: item.actionIcon)
                                }
                                .buttonStyle(SonnyMiniButtonStyle())
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(item.details, id: \.self) { detail in
                                    Label(detail, systemImage: "smallcircle.filled.circle")
                                        .font(.caption2)
                                        .foregroundStyle(SonnyTheme.muted)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
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
                        PlanPanel(plan: plan, stepStatuses: viewModel.stepStatuses)
                    }

                    if !viewModel.previews.isEmpty {
                        PreviewPanel(previews: viewModel.previews)
                    }

                    if logStore.events.isEmpty && viewModel.plan == nil && viewModel.previews.isEmpty && viewModel.finalSummary.isEmpty {
                        StartupPanel()
                    } else {
                        LogPanel(logStore: logStore)
                    }

                    if !viewModel.finalSummary.isEmpty {
                        SummaryPanel(
                            summary: viewModel.finalSummary,
                            suggestions: viewModel.suggestions,
                            copy: viewModel.copySummary,
                            runSuggestion: viewModel.runSuggestion
                        )
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
    let stepStatuses: [String: AgentStepStatus]

    var body: some View {
        Panel(title: "Plan", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                Text(plan.summary)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(SonnyTheme.text)

                ForEach(plan.steps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        StepStatusIcon(status: stepStatuses[step.id] ?? .pending)
                        Text(step.operation.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(SonnyTheme.muted)
                            .frame(width: 140, alignment: .leading)
                        Text(step.description)
                            .font(.caption)
                            .foregroundStyle(SonnyTheme.text.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct StepStatusIcon: View {
    let status: AgentStepStatus

    var body: some View {
        Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(color)
            .frame(width: 16)
            .help(status.rawValue)
    }

    private var icon: String {
        switch status {
        case .pending:
            return "circle"
        case .running:
            return "play.circle"
        case .complete:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        case .canceled:
            return "minus.circle"
        }
    }

    private var color: Color {
        switch status {
        case .pending:
            return SonnyTheme.muted
        case .running:
            return SonnyTheme.info
        case .complete:
            return SonnyTheme.accent
        case .failed:
            return SonnyTheme.danger
        case .canceled:
            return SonnyTheme.warning
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
                            .foregroundStyle(SonnyTheme.text)

                        ForEach(preview.details, id: \.self) { detail in
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(SonnyTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForEach(preview.sideEffects, id: \.self) { sideEffect in
                            Label(sideEffect, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(SonnyTheme.warning)
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
            VStack(alignment: .leading, spacing: 7) {
                ForEach(logStore.events) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Text(event.phase.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(phaseColor(event.phase))
                            .frame(width: 74, alignment: .leading)
                        Text(event.message)
                            .font(.caption)
                            .foregroundStyle(SonnyTheme.text.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func phaseColor(_ phase: AgentPhase) -> Color {
        switch phase {
        case .plan:
            return SonnyTheme.info
        case .validate:
            return SonnyTheme.lilac
        case .preview:
            return SonnyTheme.cyan
        case .confirm:
            return SonnyTheme.warning
        case .act:
            return SonnyTheme.lilac
        case .observe:
            return SonnyTheme.accent
        case .summarize:
            return SonnyTheme.muted
        }
    }
}

private struct StartupPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(SonnyTheme.accent)
                Text("Ready when you are")
                    .font(.headline)
                    .foregroundStyle(SonnyTheme.text)
            }

            StartupCapabilities()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 8)
    }
}

private struct StartupCapabilities: View {
    private let items = [
        ("Finder context", "Use selected Finder folders safely."),
        ("Chain actions", "Zip, save, reveal, and open in one request."),
        ("Routines", "Teach repeatable local workflows."),
        ("Workspaces", "Launch saved app and URL sets."),
        ("Voice", "Hold the hotkey, speak, release.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.0) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(SonnyTheme.accent)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.0)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SonnyTheme.text.opacity(0.92))
                        Text(item.1)
                            .font(.caption2)
                            .foregroundStyle(SonnyTheme.muted)
                    }
                }
            }
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
                .foregroundStyle(SonnyTheme.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SonnyTheme.info.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var latestMessage: String {
        guard let event = logStore.events.last else {
            return "Working..."
        }
        return "\(event.phase.rawValue): \(event.message)"
    }
}

private struct VoiceStatusPanel: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        HStack(spacing: 10) {
            if viewModel.isTranscribingVoice {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "waveform")
                    .foregroundStyle(SonnyTheme.danger)
            }
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(SonnyTheme.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SonnyTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var message: String {
        if viewModel.isTranscribingVoice {
            return "Transcribing voice command..."
        }
        if viewModel.isPreparingVoiceRecording {
            return "Getting microphone ready..."
        }
        return "Recording voice command..."
    }
}

private struct SummaryPanel: View {
    let summary: String
    let suggestions: [RunSuggestion]
    let copy: () -> Void
    let runSuggestion: (RunSuggestion) -> Void

    var body: some View {
        Panel(title: "Summary", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(SonnyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(action: copy) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(SonnyButtonStyle(tone: .secondary))

                    ForEach(suggestions) { suggestion in
                        Button {
                            runSuggestion(suggestion)
                        } label: {
                            Label(suggestion.title, systemImage: icon(for: suggestion))
                        }
                        .buttonStyle(SonnyButtonStyle(tone: .secondary))
                    }
                }
            }
        }
    }

    private func icon(for suggestion: RunSuggestion) -> String {
        switch suggestion.kind {
        case .revealInFinder:
            return "folder"
        case .openFile:
            return "doc.text"
        }
    }
}

private struct ClarificationPanel: View {
    @ObservedObject var viewModel: AgentViewModel
    let question: String

    var body: some View {
        Panel(title: "Clarify", systemImage: "questionmark.bubble") {
            VStack(alignment: .leading, spacing: 8) {
                Text(question)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(SonnyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TextField("Answer", text: $viewModel.clarificationAnswer)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(SonnyTheme.input)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(SonnyTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onSubmit {
                            viewModel.submitClarification()
                        }
                    Button {
                        viewModel.submitClarification()
                    } label: {
                        Label("Continue", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(SonnyButtonStyle(tone: .primary))
                    .disabled(viewModel.clarificationAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                .foregroundStyle(SonnyTheme.danger)
            Text(message)
                .font(.caption)
                .foregroundStyle(SonnyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SonnyTheme.danger.opacity(0.12))
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
                .foregroundStyle(SonnyTheme.text)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 8)
    }
}

private enum SonnyTheme {
    static let glassShade = Color(red: 0.028, green: 0.032, blue: 0.030).opacity(0.58)
    static let panelTint = Color(red: 0.045, green: 0.047, blue: 0.050).opacity(0.66)
    static let surfaceRaised = Color(red: 0.128, green: 0.126, blue: 0.134).opacity(0.78)
    static let input = Color(red: 0.070, green: 0.073, blue: 0.076).opacity(0.72)
    static let border = Color(red: 0.245, green: 0.248, blue: 0.244).opacity(0.64)
    static let text = Color(red: 0.925, green: 0.908, blue: 0.872)
    static let muted = Color(red: 0.626, green: 0.612, blue: 0.574)
    static let accent = Color(red: 0.690, green: 0.880, blue: 0.615)
    static let warning = Color(red: 0.930, green: 0.655, blue: 0.350)
    static let danger = Color(red: 0.940, green: 0.390, blue: 0.405)
    static let info = Color(red: 0.470, green: 0.690, blue: 0.920)
    static let cyan = Color(red: 0.390, green: 0.760, blue: 0.730)
    static let lilac = Color(red: 0.700, green: 0.600, blue: 0.900)
}

private extension View {
    func glassPanel(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(SonnyTheme.panelTint)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(SonnyTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

private struct SonnyButtonStyle: ButtonStyle {
    let tone: Tone

    enum Tone {
        case primary
        case secondary
        case danger
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background.opacity(configuration.isPressed ? 0.72 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var foreground: Color {
        switch tone {
        case .primary:
            return Color(red: 0.050, green: 0.055, blue: 0.048)
        case .secondary:
            return SonnyTheme.text
        case .danger:
            return SonnyTheme.text
        }
    }

    private var background: Color {
        switch tone {
        case .primary:
            return SonnyTheme.accent
        case .secondary:
            return SonnyTheme.surfaceRaised
        case .danger:
            return SonnyTheme.danger.opacity(0.58)
        }
    }

    private var border: Color {
        switch tone {
        case .primary:
            return SonnyTheme.accent.opacity(0.88)
        case .secondary:
            return SonnyTheme.border
        case .danger:
            return SonnyTheme.danger.opacity(0.7)
        }
    }
}

private struct SonnyIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(SonnyTheme.muted)
            .frame(width: 30, height: 30)
            .background(configuration.isPressed ? SonnyTheme.surfaceRaised : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SonnyMiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption2.weight(.semibold))
            .foregroundStyle(SonnyTheme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(SonnyTheme.surfaceRaised.opacity(configuration.isPressed ? 0.55 : 0.86))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(SonnyTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
