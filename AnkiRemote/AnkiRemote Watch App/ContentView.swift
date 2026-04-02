//
//  ContentView.swift
//  AnkiRemote Watch App
//
//  Created by Emir B on 4/2/26.
//

import CoreMotion
import SwiftUI

struct ContentView: View {
    private let crownThreshold: Double = 3.0

    @State private var server = ServerConnection()
    @State private var lastResult: String = ""
    @State private var isLoading = false
    @State private var motionDetector = MotionDetector()
    @State private var crownValue: Double = 0.0
    @State private var lastCrownAction: Date = .distantPast
    @State private var showCustom = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ActionButton(
                        title: "Again",
                        subtitle: "1",
                        color: .red
                    ) {
                        await sendCommand("/answer/again")
                    }

                    ActionButton(
                        title: "Good",
                        subtitle: "3",
                        color: .green
                    ) {
                        await sendCommand("/answer/good")
                    }
                }

                // Hidden button for Double Tap
                Button {
                    Task { await sendCommand("/reveal") }
                } label: {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .handGestureShortcut(.primaryAction)

                HStack(spacing: 4) {
                    Circle()
                        .fill(server.baseURL != nil ? .green : .red)
                        .frame(width: 6, height: 6)
                    if !lastResult.isEmpty {
                        Text(lastResult)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(isLoading ? .yellow : (lastResult == "OK" ? .green : .red))
                    } else if server.baseURL == nil {
                        Text("Searching…")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                }

                crownIndicator

                NavigationLink {
                    CustomCommandsView(server: server)
                } label: {
                    Text("Custom")

                }
                .font(.caption2)
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .toolbar(.hidden)
            .focusable()
            .digitalCrownRotation(
                $crownValue,
                from: -crownThreshold,
                through: crownThreshold,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: false
            )
            .onChange(of: crownValue) { oldValue, newValue in
                let now = Date()
                guard now.timeIntervalSince(lastCrownAction) > 0.8 else {
                    crownValue = 0
                    return
                }
                if newValue >= crownThreshold {
                    lastCrownAction = now
                    crownValue = 0
                    Task { await sendCommand("/answer/good") }
                } else if newValue <= -crownThreshold {
                    lastCrownAction = now
                    crownValue = 0
                    Task { await sendCommand("/answer/again") }
                }
            }
        }
        .onAppear {
            server.start()
            motionDetector.onShake = {
                Task { await sendCommand("/undo") }
            }
            motionDetector.onFlick = {
                Task { await sendCommand("/replay") }
            }
            motionDetector.start()
        }
        .onDisappear {
            motionDetector.stop()
            server.stop()
        }
    }

    private var crownIndicator: some View {
        HStack(spacing: 4) {
            Text("Again")
                .font(.system(size: 9))
                .foregroundStyle(.red.opacity(0.7))
            GeometryReader { geo in
                let width = geo.size.width
                let center = width / 2
                let offset = (crownValue / crownThreshold) * center
                ZStack {
                    Capsule()
                        .fill(.gray.opacity(0.3))
                        .frame(height: 4)
                    Circle()
                        .fill(crownValue > 0 ? .green : crownValue < 0 ? .red : .white)
                        .frame(width: 8, height: 8)
                        .offset(x: offset)
                }
                .frame(height: 8)
                .position(x: center, y: geo.size.height / 2)
            }
            .frame(height: 8)
            Text("Good")
                .font(.system(size: 9))
                .foregroundStyle(.green.opacity(0.7))
        }
    }

    func sendCommand(_ path: String) async {
        isLoading = true
        defer { isLoading = false }

        guard let baseURL = server.baseURL else {
            lastResult = "No server"
            return
        }

        guard let url = URL(string: baseURL + path) else {
            lastResult = "Bad URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4

        // Disable cookies/cache for raw speed
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                lastResult = "OK"
            } else {
                lastResult = "Error"
            }
        } catch {
            lastResult = error.localizedDescription
        }
    }
}

struct CustomCommandsView: View {
    let server: ServerConnection

    @State private var lastResult: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 8
                ) {
                    ForEach(1...9, id: \.self) { n in
                        Button {
                            Task { await sendCommand("/custom/\(n)") }
                        } label: {
                            Text("\(n)")
                                .font(.body.monospacedDigit())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                    Button {
                        Task { await sendCommand("/custom/0") }
                    } label: {
                        Text("0")
                            .font(.body.monospacedDigit())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                if !lastResult.isEmpty {
                    Text(lastResult)
                        .font(.caption2)
                        .foregroundStyle(lastResult == "OK" ? .green : .red)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Custom")
    }

    private func sendCommand(_ path: String) async {
        guard let baseURL = server.baseURL else {
            lastResult = "No server"
            return
        }

        guard let url = URL(string: baseURL + path) else {
            lastResult = "Bad URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                lastResult = "OK"
            } else {
                lastResult = "Error"
            }
        } catch {
            lastResult = error.localizedDescription
        }
    }
}

@Observable
class MotionDetector {
    private let motionManager = CMMotionManager()
    private let shakeThreshold: Double = 2.5
    private let flickThreshold: Double = 5.0
    private let cooldown: TimeInterval = 1.0
    private var lastShakeTime: Date = .distantPast
    private var lastFlickTime: Date = .distantPast

    var onShake: (() -> Void)?
    var onFlick: (() -> Void)?

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.05
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let now = Date()

            // Shake detection via user acceleration
            let accel = motion.userAcceleration
            let accelMagnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
            if accelMagnitude > shakeThreshold && now.timeIntervalSince(lastShakeTime) > cooldown {
                lastShakeTime = now
                onShake?()
            }

            // Wrist flick detection via gyroscope rotation around X axis
            let rotationX = motion.rotationRate.x
            if rotationX < -flickThreshold && now.timeIntervalSince(lastFlickTime) > cooldown {
                lastFlickTime = now
                onFlick?()
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

struct ActionButton: View {
    let title: String
    let subtitle: String
    let color: Color
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }
}

#Preview {
    ContentView()
}
