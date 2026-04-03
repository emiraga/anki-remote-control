//
//  ServerConnection.swift
//  AnkiRemote Watch App
//

import Foundation
import Network
import Observation

@Observable
class ServerConnection {
    private var browser: NWBrowser?

    private(set) var baseURL: String?

    func start() {
        guard browser == nil else { return }
        if baseURL != nil { return }
        startBrowsing()
    }

    func rediscover() {
        baseURL = nil
        stopBrowsing()
        startBrowsing()
    }

    private func startBrowsing() {
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_ankiremote._tcp.", domain: nil),
            using: NWParameters()
        )
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            if let result = results.first {
                resolveBaseURL(from: result)
                stopBrowsing()
            } else {
                baseURL = nil
            }
        }

        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.stopBrowsing()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.startBrowsing()
                }
            }
        }

        browser.start(queue: .main)
    }

    private func resolveBaseURL(from result: NWBrowser.Result) {
        if case let .bonjour(txtRecord) = result.metadata,
           let ip = txtRecord.dictionary["ip"],
           let portStr = txtRecord.dictionary["port"],
           let port = Int(portStr)
        {
            baseURL = "http://\(ip):\(port)"
        }
    }

    private func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    func stop() {
        stopBrowsing()
        baseURL = nil
    }
}
