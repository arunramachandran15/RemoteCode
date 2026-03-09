import Foundation

/// Discovers Remote Cursor bridges advertised via Bonjour (_remotecursor._tcp).
/// Same app can connect using HTTP to the discovered host:port (same API as Wi‑Fi URL).
final class BonjourBrowser: NSObject, ObservableObject {
    static let serviceType = "_remotecursor._tcp"

    @Published var discoveredServices: [DiscoveredBonjourService] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    private var browser: NSNetServiceBrowser?
    private var resolvingServices: [NSNetService] = []
    private var resolved: [String: DiscoveredBonjourService] = [:] // name -> service
    private let queue = DispatchQueue.main

    struct DiscoveredBonjourService: Identifiable {
        let id: String
        let name: String
        let host: String
        let port: Int

        var baseURL: String {
            if host.contains(":") {
                return "http://[\(host)]:\(port)"
            }
            return "http://\(host):\(port)"
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.errorMessage = nil
            self?.discoveredServices = []
            self?.resolved = [:]
            self?.resolvingServices.forEach { $0.stop() }
            self?.resolvingServices = []
            self?.browser?.stop()
            let b = NSNetServiceBrowser()
            b.delegate = self
            self?.browser = b
            b.searchForServices(ofType: Self.serviceType, inDomain: "")
            self?.isSearching = true
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.browser?.stop()
            self?.browser = nil
            self?.resolvingServices.forEach { $0.stop() }
            self?.resolvingServices = []
            self?.isSearching = false
            self?.discoveredServices = []
        }
    }

    private func addResolved(_ service: DiscoveredBonjourService) {
        resolved[service.name] = service
        discoveredServices = Array(resolved.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension BonjourBrowser: NSNetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NSNetServiceBrowser, didFind service: NSNetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 5)
        resolvingServices.append(service)
    }

    func netServiceBrowser(_ browser: NSNetServiceBrowser, didRemove service: NSNetService, moreComing: Bool) {
        resolvingServices.removeAll { $0 === service }
        resolved.removeValue(forKey: service.name)
        discoveredServices = Array(resolved.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func netServiceBrowser(_ browser: NSNetServiceBrowser, didNotSearch error: [String: NSNumber]) {
        queue.async { [weak self] in
            self?.isSearching = false
            self?.errorMessage = "Bonjour search failed"
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NSNetServiceBrowser) {
        queue.async { [weak self] in
            self?.isSearching = false
        }
    }
}

extension BonjourBrowser: NSNetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NSNetService) {
        guard let host = sender.hostName, sender.port > 0 else { return }
        let port = Int(sender.port)
        let service = DiscoveredBonjourService(
            id: "\(host):\(port)",
            name: sender.name,
            host: host,
            port: port
        )
        queue.async { [weak self] in
            self?.addResolved(service)
        }
    }

    func netService(_ sender: NSNetService, didNotResolve error: [String: NSNumber]) {
        resolvingServices.removeAll { $0 === sender }
    }
}
