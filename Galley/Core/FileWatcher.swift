import Foundation

/// Watches a single file with a kqueue dispatch source — the only watcher that
/// works when the sandbox grant is one file, not its folder. Survives the
/// atomic-save dance (write temp → rename over original) used by vim, VS Code,
/// and TextEdit by re-opening the same path when the inode goes away.
final class FileWatcher {
    private let url: URL
    private let queue = DispatchQueue(label: "galley.filewatcher", qos: .userInitiated)
    private var source: DispatchSourceFileSystemObject?
    private var fd: CInt = -1
    private var debounce: DispatchWorkItem?
    private let onChange: () -> Void
    private var cancelled = false

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        queue.async { [weak self] in self?.attach(retriesLeft: 0) }
    }

    private func attach(retriesLeft: Int) {
        guard !cancelled else { return }
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // Editors that delete-then-recreate leave a brief gap; retry a few times.
            if retriesLeft > 0 {
                queue.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
                    self?.attach(retriesLeft: retriesLeft - 1)
                }
            }
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: queue
        )
        let watchedFD = fd
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let events = src.data
            if events.contains(.delete) || events.contains(.rename) {
                src.cancel()
                self.queue.asyncAfter(deadline: .now() + .milliseconds(60)) { [weak self] in
                    self?.attach(retriesLeft: 5)
                    self?.fireDebounced()
                }
            } else {
                self.fireDebounced()
            }
        }
        src.setCancelHandler {
            close(watchedFD)
        }
        source = src
        src.resume()
    }

    private func fireDebounced() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.cancelled else { return }
            DispatchQueue.main.async { self.onChange() }
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + .milliseconds(120), execute: work)
    }

    func stop() {
        cancelled = true
        queue.async { [self] in
            debounce?.cancel()
            source?.cancel()
            source = nil
        }
    }

    deinit {
        stop()
    }
}
