//
//  WorkflowService.swift
//  aizen
//
//  Observable service for managing CI/CD workflows
//

import Foundation
import Combine
import os.log

@MainActor
class WorkflowService: ObservableObject {
    // MARK: - Published State

    @Published var provider: WorkflowProvider = .none
    @Published var isLoading: Bool = false
    @Published var isInitializing: Bool = true  // Show loading on first load
    @Published var error: WorkflowError?

    @Published var workflows: [Workflow] = []
    @Published var runs: [WorkflowRun] = []
    @Published var selectedWorkflow: Workflow?
    @Published var selectedRun: WorkflowRun?
    @Published var selectedRunJobs: [WorkflowJob] = []
    @Published var runLogs: String = ""
    @Published var isLoadingLogs: Bool = false

    private var currentLogJobId: String?

    @Published var cliAvailability: CLIAvailability?

    // MARK: - Private

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "WorkflowService")
    private var repoPath: String = ""
    private var currentBranch: String = ""

    private var githubProvider: GitHubWorkflowProvider?
    private var gitlabProvider: GitLabWorkflowProvider?

    private var refreshTimer: Timer?
    private var logPollingTask: Task<Void, Never>?

    private let runsLimit = 20

    // MARK: - Initialization

    func configure(repoPath: String, branch: String) async {
        self.repoPath = repoPath
        self.currentBranch = branch
        isInitializing = true

        // Ensure shell environment is preloaded
        _ = ShellEnvironment.loadUserShellEnvironment()

        // Detect provider
        provider = await WorkflowDetector.shared.detect(repoPath: repoPath)

        // Check CLI availability
        cliAvailability = await WorkflowDetector.shared.checkCLIAvailability()

        // Initialize appropriate provider
        switch provider {
        case .github:
            githubProvider = GitHubWorkflowProvider()
        case .gitlab:
            gitlabProvider = GitLabWorkflowProvider()
        case .none:
            break
        }

        isInitializing = false

        // Initial load
        await loadWorkflows()
        await loadRuns()

        // Start auto-refresh timer (60 seconds)
        startAutoRefresh()
    }

    func updateBranch(_ branch: String) async {
        guard branch != currentBranch else { return }
        currentBranch = branch
        await loadRuns()
    }

    // MARK: - Data Loading

    func loadWorkflows() async {
        guard provider != .none else { return }

        isLoading = true
        error = nil

        do {
            workflows = try await currentProvider?.listWorkflows(repoPath: repoPath) ?? []
        } catch let workflowError as WorkflowError {
            error = workflowError
            logger.error("Failed to load workflows: \(workflowError.localizedDescription)")
        } catch {
            self.error = .executionFailed(error.localizedDescription)
            logger.error("Failed to load workflows: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func loadRuns() async {
        guard provider != .none else { return }

        isLoading = true
        error = nil

        do {
            runs = try await currentProvider?.listRuns(
                repoPath: repoPath,
                workflow: nil,
                branch: currentBranch,
                limit: runsLimit
            ) ?? []
        } catch let workflowError as WorkflowError {
            error = workflowError
            logger.error("Failed to load runs: \(workflowError.localizedDescription)")
        } catch {
            self.error = .executionFailed(error.localizedDescription)
            logger.error("Failed to load runs: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func refresh() async {
        await loadWorkflows()
        await loadRuns()

        // Refresh selected run if any
        if let selected = selectedRun {
            await selectRun(selected)
        }
    }

    // MARK: - Run Selection

    func selectRun(_ run: WorkflowRun) async {
        // Skip reload if same run is already selected and has data
        let isSameRun = selectedRun?.id == run.id
        if isSameRun && !selectedRunJobs.isEmpty {
            // Just update the run status without clearing jobs/logs
            selectedRun = run
            return
        }

        selectedRun = run
        selectedRunJobs = []
        runLogs = ""
        currentLogJobId = nil
        stopLogPolling()

        // Capture values for background tasks
        let provider = currentProvider
        let path = repoPath
        let runId = run.id

        // Load jobs in background (don't await - let it update when ready)
        Task.detached { [weak self] in
            do {
                let jobs = try await provider?.getRunJobs(repoPath: path, runId: runId) ?? []
                await MainActor.run {
                    self?.selectedRunJobs = jobs
                }
            } catch {
                // Silently fail, jobs will remain empty
            }
        }

        // Start log polling if run is in progress, otherwise load once (non-blocking)
        if run.isInProgress {
            startLogPolling(runId: run.id)
        } else {
            // Load logs in background (don't await)
            Task {
                await loadLogs(runId: run.id)
            }
        }
    }

    func clearSelection() {
        selectedWorkflow = nil
        selectedRun = nil
        selectedRunJobs = []
        runLogs = ""
        currentLogJobId = nil
        stopLogPolling()
    }

    // MARK: - Actions

    func getWorkflowInputs(workflow: Workflow) async -> [WorkflowInput] {
        do {
            return try await currentProvider?.getWorkflowInputs(repoPath: repoPath, workflow: workflow) ?? []
        } catch {
            logger.error("Failed to get workflow inputs: \(error.localizedDescription)")
            return []
        }
    }

    func triggerWorkflow(_ workflow: Workflow, branch: String, inputs: [String: String]) async -> Bool {
        isLoading = true
        error = nil

        do {
            let newRun = try await currentProvider?.triggerWorkflow(
                repoPath: repoPath,
                workflow: workflow,
                branch: branch,
                inputs: inputs
            )

            // Refresh runs list
            await loadRuns()

            // Select the new run if available
            if let run = newRun {
                await selectRun(run)
            }

            isLoading = false
            return true
        } catch let workflowError as WorkflowError {
            error = workflowError
            logger.error("Failed to trigger workflow: \(workflowError.localizedDescription)")
        } catch {
            self.error = .executionFailed(error.localizedDescription)
            logger.error("Failed to trigger workflow: \(error.localizedDescription)")
        }

        isLoading = false
        return false
    }

    func cancelRun(_ run: WorkflowRun) async -> Bool {
        isLoading = true
        error = nil

        do {
            try await currentProvider?.cancelRun(repoPath: repoPath, runId: run.id)

            // Refresh to get updated status
            await loadRuns()

            if selectedRun?.id == run.id {
                await selectRun(run)
            }

            isLoading = false
            return true
        } catch let workflowError as WorkflowError {
            error = workflowError
            logger.error("Failed to cancel run: \(workflowError.localizedDescription)")
        } catch {
            self.error = .executionFailed(error.localizedDescription)
            logger.error("Failed to cancel run: \(error.localizedDescription)")
        }

        isLoading = false
        return false
    }

    // MARK: - Logs

    func loadLogs(runId: String, jobId: String? = nil) async {
        // Skip reload if same job logs already loaded
        if let jobId = jobId, jobId == currentLogJobId, !runLogs.isEmpty {
            return
        }

        isLoadingLogs = true
        currentLogJobId = jobId

        // Capture values for background task
        let provider = currentProvider
        let path = repoPath

        do {
            // Run on background thread to avoid blocking UI
            let logs = try await Task.detached {
                try await provider?.getRunLogs(repoPath: path, runId: runId, jobId: jobId) ?? ""
            }.value
            runLogs = logs
        } catch {
            logger.error("Failed to load logs: \(error.localizedDescription)")
            runLogs = "Failed to load logs: \(error.localizedDescription)"
        }

        isLoadingLogs = false
    }

    func refreshLogs() async {
        guard let run = selectedRun else { return }
        await loadLogs(runId: run.id)
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        stopAutoRefresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Log Polling

    private func startLogPolling(runId: String) {
        stopLogPolling()

        // Capture values for background polling
        let provider = currentProvider
        let path = repoPath

        logPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadLogs(runId: runId)

                // Also refresh run status in background
                if let provider = provider {
                    do {
                        let updatedRun = try await Task.detached {
                            try await provider.getRun(repoPath: path, runId: runId)
                        }.value

                        await MainActor.run { [weak self] in
                            self?.selectedRun = updatedRun

                            // Update in runs list
                            if let index = self?.runs.firstIndex(where: { $0.id == runId }) {
                                self?.runs[index] = updatedRun
                            }

                            // Stop polling if run completed
                            if !updatedRun.isInProgress {
                                self?.stopLogPolling()
                            }
                        }

                        // Refresh jobs in background
                        let jobs = try await Task.detached {
                            try await provider.getRunJobs(repoPath: path, runId: runId)
                        }.value

                        await MainActor.run { [weak self] in
                            self?.selectedRunJobs = jobs
                        }
                    } catch {
                        // Continue polling on error
                    }
                }

                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func stopLogPolling() {
        logPollingTask?.cancel()
        logPollingTask = nil
    }

    // MARK: - Helpers

    private var currentProvider: (any WorkflowProviderProtocol)? {
        switch provider {
        case .github: return githubProvider
        case .gitlab: return gitlabProvider
        case .none: return nil
        }
    }

    var isConfigured: Bool {
        provider != .none
    }

    var isCLIInstalled: Bool {
        guard let availability = cliAvailability else { return false }
        switch provider {
        case .github: return availability.gh
        case .gitlab: return availability.glab
        case .none: return false
        }
    }

    var isAuthenticated: Bool {
        guard let availability = cliAvailability else { return false }
        switch provider {
        case .github: return availability.ghAuthenticated
        case .gitlab: return availability.glabAuthenticated
        case .none: return false
        }
    }

    var installURL: URL? {
        switch provider {
        case .github: return URL(string: "https://cli.github.com")
        case .gitlab: return URL(string: "https://gitlab.com/gitlab-org/cli")
        case .none: return nil
        }
    }

    deinit {
        refreshTimer?.invalidate()
        logPollingTask?.cancel()
    }
}
