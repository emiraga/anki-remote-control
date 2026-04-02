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
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_ankiremote._tcp.", domain: nil),
            using: NWParameters()
        )
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            if let result = results.first {
                resolveBaseURL(from: result)
            } else {
                baseURL = nil
            }
        }

        browser.stateUpdateHandler = { state in
            if case .failed = state {
                browser.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.start()
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

    func stop() {
        browser?.cancel()
        browser = nil
        baseURL = nil
    }
}
