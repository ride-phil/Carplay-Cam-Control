import Foundation

/// Cross-process change notifications via the Darwin notification center —
/// the standard mechanism for an App Group's main app and extensions to
/// signal each other that SharedState changed. UserDefaults' own
/// didChangeNotification does not reliably cross the process boundary
/// between the app and the widget extension.
enum CrossProcessNotifier {
    private static let stateChangedName = "io.camcontrol.app.stateChanged" as CFString
    private static var observers: [Observer] = []

    static func notifyStateChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(stateChangedName),
            nil, nil, true
        )
    }

    static func observeStateChanged(_ handler: @escaping () -> Void) {
        let observer = Observer(handler: handler)
        observers.append(observer)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(observer).toOpaque(),
            { _, observerPointer, _, _, _ in
                guard let observerPointer else { return }
                Unmanaged<Observer>.fromOpaque(observerPointer).takeUnretainedValue().handler()
            },
            stateChangedName,
            nil,
            .deliverImmediately
        )
    }

    private final class Observer {
        let handler: () -> Void
        init(handler: @escaping () -> Void) { self.handler = handler }
    }
}
