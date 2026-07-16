import Foundation

// Watches the directory rather than the data file: atomic saves replace the
// file's inode on every write, which would leave a file-descriptor source
// watching a dead inode after the first change.
public final class DirectoryChangeWatcher {
    private let source: any DispatchSourceFileSystemObject

    public init?(directoryURL: URL, onChange: @escaping @Sendable () -> Void) {
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.activate()
    }

    deinit {
        source.cancel()
    }
}
