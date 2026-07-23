import Foundation

/// Watches a single file with a kqueue dispatch source — the only watcher that
/// works when the sandbox grant is one file, not its folder. Survives the
/// atomic-save dance (write temp → rename over original) used by vim, VS Code,
/// and TextEdit by re-opening the same path when the inode goes away.
///
/// All mutable state is confined to `queue`. `stop()` is synchronous and never
/// captures `self` in an escaping closure, so calling it from `deinit` is safe.
final class FileWatcher {
    private let url: URL
    private let queue = DispatchQueue(label: "galley.filewatcher", qos: .userInitiated)
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var cancelled = false
    private let onChange: () -> Void
    /// Fired on the main queue if the file disappears for good and the watcher
    /// gives up — the owner should stop advertising live reload.
    private let onInvalidate: () -> Void

    init(url: URL, onChange: @escaping () -> Void, onInvalidate: @escaping () -> Void = {}) {
        self.url = url
        self.onChange = onChange
        self.onInvalidate = onInvalidate
        queue.async { [weak self] in self?.attach(retriesLeft: 0, afterReplace: false) }
    }

    /// Runs on `queue`.
    private func attach(retriesLeft: Int, afterReplace: Bool) {
        guard !cancelled else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            if retriesLeft > 0 {
                // Editors that delete-then-recreate leave a gap; keep trying
                // for a while before declaring the file gone.
                queue.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
                    self?.attach(retriesLeft: retriesLeft - 1, afterReplace: afterReplace)
                }
            } else if afterReplace {
                DispatchQueue.main.async(execute: onInvalidate)
            }
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let events = src.data
            if events.contains(.delete) || events.contains(.rename) {
                src.cancel()
                self.queue.asyncAfter(deadline: .now() + .milliseconds(60)) { [weak self] in
                    // Re-attaching to the replacement file counts as a change;
                    // attach() fires the callback once it has the new inode.
                    self?.attach(retriesLeft: 10, afterReplace: true)
                }
            } else {
                self.fireDebounced()
            }
        }
        src.setCancelHandler {
            close(fd)
        }
        source = src
        src.resume()

        if afterReplace {
            fireDebounced()
        }
    }

    /// Runs on `queue`.
    private func fireDebounced() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.cancelled else { return }
            DispatchQueue.main.async(execute: self.onChange)
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + .milliseconds(120), execute: work)
    }

    func stop() {
        queue.sync {
            cancelled = true
            debounce?.cancel()
            debounce = nil
            source?.cancel()
            source = nil
        }
    }

    deinit {
        stop()
    }
}
