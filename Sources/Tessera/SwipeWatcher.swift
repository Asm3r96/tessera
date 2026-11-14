import AppKit
import TesseraCore

/// Reads raw trackpad touches through the private MultitouchSupport framework.
/// macOS sends page swipes only to the app under the pointer, so Tessera cannot watch those events.
final class SwipeWatcher {
    var onSwipe: (Int, CGPoint) -> Bool = { _, _ in false }

    private typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

    private struct API {
        let createList: @convention(c) () -> Unmanaged<CFArray>
        let register: @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
        let unregister: @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
        let start: @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
        let stop: @convention(c) (UnsafeMutableRawPointer) -> Void

        static func load() -> API? {
            guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
                  let createList = dlsym(handle, "MTDeviceCreateList"),
                  let register = dlsym(handle, "MTRegisterContactFrameCallback"),
                  let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
                  let start = dlsym(handle, "MTDeviceStart"),
                  let stop = dlsym(handle, "MTDeviceStop") else { return nil }
            return API(createList: unsafeBitCast(createList, to: (@convention(c) () -> Unmanaged<CFArray>).self),
                       register: unsafeBitCast(register, to: (@convention(c) (UnsafeMutableRawPointer, Callback) -> Void).self),
                       unregister: unsafeBitCast(unregister, to: (@convention(c) (UnsafeMutableRawPointer, Callback) -> Void).self),
                       start: unsafeBitCast(start, to: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Void).self),
                       stop: unsafeBitCast(stop, to: (@convention(c) (UnsafeMutableRawPointer) -> Void).self))
        }
    }

    // MTTouch layout: 96 bytes per touch, state at 20, normalized position at 32 and 36.
    private static let touchSize = 96
    private static let touching: ClosedRange<Int32> = 3...4

    private static weak var current: SwipeWatcher?
    private static let callback: Callback = { device, touches, count, _, _ in
        guard let touches, let watcher = SwipeWatcher.current else { return 0 }
        var points: [CGPoint] = []
        for index in 0..<Int(count) {
            let touch = touches + index * touchSize
            guard touching.contains(touch.load(fromByteOffset: 20, as: Int32.self)) else { continue }
            points.append(CGPoint(x: Double(touch.load(fromByteOffset: 32, as: Float.self)),
                                  y: Double(touch.load(fromByteOffset: 36, as: Float.self))))
        }
        watcher.frame(points, device: Int(bitPattern: device))
        return 0
    }

    private let api = API.load()
    private var list: CFArray?
    private var devices: [UnsafeMutableRawPointer] = []
    private let lock = NSLock()
    private var trackers: [Int: TabSwipe] = [:]
    private var wakeObserver: NSObjectProtocol?

    func start() {
        guard let api else {
            NSLog("Tessera: MultitouchSupport is not available; trackpad swipes are off")
            return
        }
        guard devices.isEmpty else { return }
        SwipeWatcher.current = self
        let list = api.createList().takeRetainedValue()
        self.list = list
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            let pointer = UnsafeMutableRawPointer(mutating: device)
            api.register(pointer, SwipeWatcher.callback)
            api.start(pointer, 0)
            devices.append(pointer)
        }
        // Touch devices stop sending frames after sleep, so start them again on wake.
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.stop()
                self?.start()
            }
        }
    }

    private func stop() {
        guard let api else { return }
        for device in devices {
            api.unregister(device, SwipeWatcher.callback)
            api.stop(device)
        }
        devices = []
        list = nil
        lock.lock()
        trackers = [:]
        lock.unlock()
    }

    deinit {
        stop()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    /// Runs on the MultitouchSupport thread.
    private func frame(_ points: [CGPoint], device: Int) {
        lock.lock()
        let offset = trackers[device, default: TabSwipe()].update(points)
        lock.unlock()
        guard let offset else { return }
        DispatchQueue.main.async { [weak self] in
            _ = self?.onSwipe(offset, Screens.mouse)
        }
    }
}
