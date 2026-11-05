import SwiftUI
import Combine

enum Status: Equatable {
    case idle, working, done
    case failed(String)
}

@MainActor
final class Item: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let ext: String
    let kind: Kind
    @Published var target: String
    @Published var status: Status = .idle
    @Published var progress: Double = 0
    @Published var output: URL?

    init?(url: URL) {
        let e = Formats.norm(url.pathExtension)
        guard let k = Formats.kind(of: e) else { return nil }
        self.url = url
        self.ext = e
        self.kind = k
        let opts = k.outputs.filter { $0 != e }
        self.target = opts.contains(k.defaultTarget) ? k.defaultTarget : (opts.first ?? "")
    }

    var options: [String] { kind.outputs.filter { $0 != ext } }
}

@MainActor
final class Store: ObservableObject {
    @Published var items: [Item] = []
    @Published var busy = false
    @Published var rejected = ""
    @Published var showRejected = false
    private var bag = Set<AnyCancellable>()

    func add(_ urls: [URL]) {
        var bad: [String] = []
        let explicit = Set(urls)
        for u in Expand.files(urls) {
            if items.contains(where: { $0.url == u }) { continue }
            if let it = Item(url: u) {
                it.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
                items.append(it)
            } else if explicit.contains(u) {
                bad.append(u.lastPathComponent)
            }
        }
        if !bad.isEmpty {
            rejected = bad.joined(separator: "\n")
            showRejected = true
        }
    }

    func remove(_ item: Item) { items.removeAll { $0.id == item.id } }
    func clear() { items.removeAll() }

    var commonTargets: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for it in items {
            for t in it.options where !seen.contains(t) {
                seen.insert(t)
                list.append(t)
            }
        }
        return list
    }

    func setAll(_ t: String) {
        for it in items where it.options.contains(t) {
            it.target = t
            if it.status != .working { it.status = .idle }
        }
    }

    var hasWork: Bool { items.contains { $0.status != .done } }

    func convertAll() {
        guard !busy else { return }
        busy = true
        Task {
            for item in items where item.status != .done {
                item.status = .working
                item.progress = 0
                do {
                    let out = try await Converter.convert(item.url, kind: item.kind, ext: item.ext, target: item.target) { p in
                        Task { @MainActor in item.progress = p }
                    }
                    item.output = out
                    item.status = .done
                } catch {
                    item.status = .failed(error.localizedDescription)
                }
            }
            busy = false
        }
    }
}
