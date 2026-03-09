import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readSource: DispatchSourceRead?

    func applicationDidFinishLaunching(_ notification: Notification) {
        captureStdoutStderr()
        BridgeRunner.start()
    }

    private func captureStdoutStderr() {
        let logStore = LogStore.shared

        func makePipe() -> (Pipe, FileHandle) {
            let pipe = Pipe()
            pipe.fileHandleForReading.readabilityHandler = { [weak logStore] fh in
                let data = fh.availableData
                guard !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else { return }
                text.split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                    .forEach { logStore?.append($0) }
            }
            return (pipe, pipe.fileHandleForWriting)
        }

        let (outPipe, outWrite) = makePipe()
        let (errPipe, errWrite) = makePipe()
        stdoutPipe = outPipe
        stderrPipe = errPipe

        let outFd = outWrite.fileDescriptor
        let errFd = errWrite.fileDescriptor
        setvbuf(stdout, nil, _IONBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)
        dup2(outFd, STDOUT_FILENO)
        dup2(errFd, STDERR_FILENO)
        outWrite.closeFile()
        errWrite.closeFile()
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
