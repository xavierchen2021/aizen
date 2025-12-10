//
//  XcodeDeviceService.swift
//  aizen
//
//  Created by Claude on 10.12.25.
//

import Foundation
import os.log

actor XcodeDeviceService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeDeviceService")

    // MARK: - List Destinations

    func listDestinations() async throws -> [DestinationType: [XcodeDestination]] {
        var destinations: [DestinationType: [XcodeDestination]] = [:]

        // Get simulators
        let simulators = try await listSimulators()
        if !simulators.isEmpty {
            destinations[.simulator] = simulators
        }

        // Get physical devices
        let devices = try await listPhysicalDevices()
        if !devices.isEmpty {
            destinations[.device] = devices
        }

        // Add My Mac
        destinations[.mac] = [createMacDestination()]

        return destinations
    }

    // MARK: - Simulators

    private func listSimulators() async throws -> [XcodeDestination] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "--json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            logger.error("simctl list devices failed")
            return []
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(SimctlDevicesResponse.self, from: data)

        var destinations: [XcodeDestination] = []

        for (runtime, devices) in response.devices {
            // Parse runtime: com.apple.CoreSimulator.SimRuntime.iOS-17-0
            let runtimeComponents = runtime.components(separatedBy: ".")
            guard let lastComponent = runtimeComponents.last else { continue }

            // Parse platform and version: iOS-17-0 -> iOS, 17.0
            let platformVersion = lastComponent.components(separatedBy: "-")
            guard platformVersion.count >= 2 else { continue }

            let platform = platformVersion[0]
            let version = platformVersion.dropFirst().joined(separator: ".")

            // Filter to iOS and common platforms
            guard ["iOS", "watchOS", "tvOS", "visionOS"].contains(platform) else { continue }

            for device in devices {
                // Skip unavailable simulators
                guard device.isAvailable else { continue }

                let destination = XcodeDestination(
                    id: device.udid,
                    name: device.name,
                    type: .simulator,
                    platform: platform,
                    osVersion: version,
                    isAvailable: device.isAvailable
                )
                destinations.append(destination)
            }
        }

        // Sort by platform, then by version (newest first), then by name
        destinations.sort { lhs, rhs in
            if lhs.platform != rhs.platform {
                // iOS first
                if lhs.platform == "iOS" { return true }
                if rhs.platform == "iOS" { return false }
                return lhs.platform < rhs.platform
            }
            if lhs.osVersion != rhs.osVersion {
                return (lhs.osVersion ?? "") > (rhs.osVersion ?? "")
            }
            return lhs.name < rhs.name
        }

        return destinations
    }

    // MARK: - Physical Devices

    private func listPhysicalDevices() async throws -> [XcodeDestination] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xctrace", "list", "devices"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var destinations: [XcodeDestination] = []
        var isInDevicesSection = false

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Look for device section header
            if trimmed.hasPrefix("== Devices ==") {
                isInDevicesSection = true
                continue
            }

            // Stop at simulators section
            if trimmed.hasPrefix("== Simulators ==") {
                break
            }

            guard isInDevicesSection, !trimmed.isEmpty else { continue }

            // Parse device line: "iPhone Name (16.0) (UDID-HERE)"
            if let destination = parseDeviceLine(trimmed) {
                destinations.append(destination)
            }
        }

        return destinations
    }

    private func parseDeviceLine(_ line: String) -> XcodeDestination? {
        // Format: "Device Name (OS Version) (UDID)"
        // or: "Device Name (UDID)" for Mac

        // Extract UDID from last parentheses
        guard let lastOpenParen = line.lastIndex(of: "("),
              let lastCloseParen = line.lastIndex(of: ")"),
              lastOpenParen < lastCloseParen else {
            return nil
        }

        let udidStart = line.index(after: lastOpenParen)
        let udid = String(line[udidStart..<lastCloseParen])

        // Skip if UDID looks like a version number
        guard udid.contains("-") || udid.count > 10 else { return nil }

        // Get everything before the UDID
        let beforeUdid = String(line[..<lastOpenParen]).trimmingCharacters(in: .whitespaces)

        // Check for version in second-to-last parentheses
        var name = beforeUdid
        var version: String? = nil

        if let versionOpenParen = beforeUdid.lastIndex(of: "("),
           let versionCloseParen = beforeUdid.lastIndex(of: ")"),
           versionOpenParen < versionCloseParen {
            let versionStart = beforeUdid.index(after: versionOpenParen)
            let possibleVersion = String(beforeUdid[versionStart..<versionCloseParen])

            // Check if it looks like a version
            if possibleVersion.first?.isNumber == true {
                version = possibleVersion
                name = String(beforeUdid[..<versionOpenParen]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Skip This Mac (we add it separately)
        if name.lowercased().contains("mac") && !name.lowercased().contains("iphone") {
            return nil
        }

        // Determine platform
        let platform: String
        if name.lowercased().contains("iphone") || name.lowercased().contains("ipad") {
            platform = "iOS"
        } else if name.lowercased().contains("watch") {
            platform = "watchOS"
        } else if name.lowercased().contains("tv") {
            platform = "tvOS"
        } else {
            platform = "iOS" // Default
        }

        return XcodeDestination(
            id: udid,
            name: name,
            type: .device,
            platform: platform,
            osVersion: version,
            isAvailable: true
        )
    }

    private func createMacDestination() -> XcodeDestination {
        var macName = "My Mac"

        // Get Mac model name
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "-detailLevel", "mini"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: "\n") {
                    if line.contains("Model Name:") {
                        let parts = line.components(separatedBy: ":")
                        if parts.count >= 2 {
                            macName = parts[1].trimmingCharacters(in: .whitespaces)
                        }
                        break
                    }
                }
            }
        } catch {
            logger.warning("Failed to get Mac model name")
        }

        return XcodeDestination(
            id: "macos",
            name: macName,
            type: .mac,
            platform: "macOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            isAvailable: true
        )
    }

    // MARK: - Simulator Control

    func bootSimulatorIfNeeded(id: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "boot", id]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        // Exit code 149 means already booted, which is fine
        if process.terminationStatus != 0 && process.terminationStatus != 149 {
            logger.warning("Failed to boot simulator \(id), exit code: \(process.terminationStatus)")
        }
    }

    func launchInSimulator(deviceId: String, bundleId: String) async throws {
        // First boot the simulator
        try await bootSimulatorIfNeeded(id: deviceId)

        // Small delay to ensure simulator is ready
        try await Task.sleep(nanoseconds: 500_000_000)

        // Launch the app
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "launch", deviceId, bundleId]

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw XcodeError.launchFailed(errorMessage)
        }
    }

    func openSimulatorApp() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Simulator"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try? process.run()
    }
}
