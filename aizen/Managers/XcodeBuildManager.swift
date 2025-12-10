//
//  XcodeBuildManager.swift
//  aizen
//
//  Created by Claude on 10.12.25.
//

import Foundation
import SwiftUI
import Combine
import os.log

class XcodeBuildManager: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeBuildManager")

    // MARK: - Published State

    @Published var currentPhase: BuildPhase = .idle
    @Published var detectedProject: XcodeProject?
    @Published var selectedScheme: String?
    @Published var selectedDestination: XcodeDestination?
    @Published var availableDestinations: [DestinationType: [XcodeDestination]] = [:]
    @Published var lastBuildLog: String?
    @Published var lastBuildDuration: TimeInterval?
    @Published var isLoadingDestinations = false
    @Published private(set) var isReady = false

    // Track if destinations have been loaded to prevent double loading
    private var destinationsLoaded = false

    // MARK: - Persistence

    private var lastDestinationId: String {
        get { UserDefaults.standard.string(forKey: "xcodeLastDestinationId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "xcodeLastDestinationId") }
    }

    private var projectSchemeKey: String {
        guard let project = detectedProject else { return "" }
        return "xcodeScheme_\(project.path.hashValue)"
    }

    // MARK: - Services

    private let projectDetector = XcodeProjectDetector()
    private let deviceService = XcodeDeviceService()
    private let buildService = XcodeBuildService()

    private var buildTask: Task<Void, Never>?
    private var currentWorktreePath: String?

    init() {}

    // MARK: - Detection

    func detectProject(at path: String) {
        guard path != currentWorktreePath else { return }
        currentWorktreePath = path

        // Reset state
        detectedProject = nil
        selectedScheme = nil
        currentPhase = .idle
        lastBuildLog = nil
        isReady = false
        destinationsLoaded = false

        Task { [weak self] in
            guard let self = self else { return }

            // Detect project
            let project = await self.projectDetector.detectProject(at: path)

            guard let project = project else {
                self.logger.debug("No Xcode project found at \(path)")
                return
            }

            self.logger.info("Detected Xcode project: \(project.displayName) with \(project.schemes.count) schemes")

            // Load destinations first (before showing UI)
            await self.loadDestinations()

            // Now set project and scheme on main actor (this makes UI visible)
            await MainActor.run {
                self.detectedProject = project

                // Restore or auto-select scheme
                let savedScheme = UserDefaults.standard.string(forKey: self.projectSchemeKey)
                if let saved = savedScheme, project.schemes.contains(saved) {
                    self.selectedScheme = saved
                } else if project.schemes.count == 1 {
                    self.selectedScheme = project.schemes.first
                }

                // Mark as ready only after everything is loaded
                self.isReady = true
            }
        }
    }

    func refreshDestinations() {
        Task { [weak self] in
            await self?.loadDestinations(force: true)
        }
    }

    private func loadDestinations(force: Bool = false) async {
        // Prevent double loading unless forced (refresh button)
        if destinationsLoaded && !force {
            return
        }

        await MainActor.run {
            isLoadingDestinations = true
        }

        do {
            let destinations = try await deviceService.listDestinations()

            await MainActor.run {
                self.availableDestinations = destinations
                self.destinationsLoaded = true

                // Restore last selected destination or pick first simulator
                if let lastId = self.lastDestinationId.isEmpty ? nil : self.lastDestinationId,
                   let destination = self.findDestination(byId: lastId) {
                    self.selectedDestination = destination
                } else if self.selectedDestination == nil {
                    // Default to first iOS simulator
                    self.selectedDestination = destinations[.simulator]?.first { $0.platform == "iOS" }
                        ?? destinations[.mac]?.first
                }
            }

            logger.info("Loaded \(destinations.values.flatMap { $0 }.count) destinations")
        } catch {
            logger.error("Failed to load destinations: \(error.localizedDescription)")
        }

        await MainActor.run {
            isLoadingDestinations = false
        }
    }

    private func findDestination(byId id: String) -> XcodeDestination? {
        for (_, destinations) in availableDestinations {
            if let destination = destinations.first(where: { $0.id == id }) {
                return destination
            }
        }
        return nil
    }

    // MARK: - Scheme Selection

    func selectScheme(_ scheme: String) {
        selectedScheme = scheme
        UserDefaults.standard.set(scheme, forKey: projectSchemeKey)
    }

    // MARK: - Destination Selection

    func selectDestination(_ destination: XcodeDestination) {
        selectedDestination = destination
        lastDestinationId = destination.id
    }

    // MARK: - Build & Run

    func buildAndRun() {
        guard let project = detectedProject,
              let scheme = selectedScheme,
              let destination = selectedDestination else {
            logger.warning("Cannot build: missing project, scheme, or destination")
            return
        }

        // Cancel any existing build
        cancelBuild()

        let startTime = Date()

        buildTask = Task { [weak self] in
            guard let self = self else { return }

            for await phase in await self.buildService.buildAndRun(
                project: project,
                scheme: scheme,
                destination: destination
            ) {
                await MainActor.run {
                    self.currentPhase = phase

                    // Store log on failure
                    if case .failed(_, let log) = phase {
                        self.lastBuildLog = log
                        self.lastBuildDuration = Date().timeIntervalSince(startTime)
                    }

                    // Handle success
                    if case .succeeded = phase {
                        self.lastBuildDuration = Date().timeIntervalSince(startTime)
                        self.lastBuildLog = nil

                        // Launch app
                        if destination.type == .simulator {
                            Task {
                                await self.launchInSimulator(project: project, scheme: scheme, destination: destination)
                            }
                        } else if destination.type == .mac {
                            Task {
                                await self.launchOnMac(project: project, scheme: scheme)
                            }
                        }
                    }
                }
            }
        }
    }

    private func launchInSimulator(project: XcodeProject, scheme: String, destination: XcodeDestination) async {
        await MainActor.run {
            currentPhase = .launching
        }

        // Open Simulator app
        await deviceService.openSimulatorApp()

        do {
            // Get bundle identifier
            let bundleId = try await projectDetector.getBundleIdentifier(project: project, scheme: scheme)

            guard let bundleId = bundleId else {
                logger.warning("Could not determine bundle identifier for launch")
                await MainActor.run {
                    currentPhase = .succeeded
                }
                return
            }

            // Launch the app
            try await deviceService.launchInSimulator(deviceId: destination.id, bundleId: bundleId)
            await MainActor.run {
                currentPhase = .succeeded
            }
        } catch {
            logger.error("Failed to launch in simulator: \(error.localizedDescription)")
            await MainActor.run {
                currentPhase = .failed(error: "Launch failed: \(error.localizedDescription)", log: "")
            }
        }
    }

    private func launchOnMac(project: XcodeProject, scheme: String) async {
        await MainActor.run {
            currentPhase = .launching
        }

        do {
            // Find the built app in DerivedData
            let appPath = try await findBuiltApp(project: project, scheme: scheme)

            guard let appPath = appPath else {
                logger.warning("Could not find built app")
                await MainActor.run {
                    currentPhase = .succeeded
                }
                return
            }

            // Launch the app using open command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [appPath]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            await MainActor.run {
                currentPhase = .succeeded
            }
        } catch {
            logger.error("Failed to launch on Mac: \(error.localizedDescription)")
            await MainActor.run {
                currentPhase = .failed(error: "Launch failed: \(error.localizedDescription)", log: "")
            }
        }
    }

    private func findBuiltApp(project: XcodeProject, scheme: String) async throws -> String? {
        // Get the build settings to find the built product path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")

        var arguments = ["-showBuildSettings", "-scheme", scheme]
        if project.isWorkspace {
            arguments.append(contentsOf: ["-workspace", project.path])
        } else {
            arguments.append(contentsOf: ["-project", project.path])
        }
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Look for BUILT_PRODUCTS_DIR and FULL_PRODUCT_NAME
        var builtProductsDir: String?
        var productName: String?

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("BUILT_PRODUCTS_DIR = ") {
                builtProductsDir = String(trimmed.dropFirst("BUILT_PRODUCTS_DIR = ".count))
            } else if trimmed.hasPrefix("FULL_PRODUCT_NAME = ") {
                productName = String(trimmed.dropFirst("FULL_PRODUCT_NAME = ".count))
            }
        }

        guard let dir = builtProductsDir, let name = productName else { return nil }

        let appPath = (dir as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: appPath) {
            return appPath
        }

        return nil
    }

    func cancelBuild() {
        buildTask?.cancel()
        buildTask = nil
        Task {
            await buildService.cancelBuild()
        }
        if currentPhase.isBuilding {
            currentPhase = .idle
        }
    }

    // MARK: - Reset

    func resetStatus() {
        if !currentPhase.isBuilding {
            currentPhase = .idle
            lastBuildLog = nil
        }
    }
}
