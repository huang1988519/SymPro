import SwiftUI

#if os(macOS)
import AppKit

/// Observes the host NSWindow's close event from SwiftUI.
struct WindowWillCloseObserver: NSViewRepresentable {
    var onWindowAvailable: ((NSWindow) -> Void)? = nil
    var shouldClose: (() -> Bool)? = nil
    var onWillClose: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onWindowAvailable: onWindowAvailable,
            shouldClose: shouldClose,
            onWillClose: onWillClose
        )
    }

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: v.window)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private let onWindowAvailable: ((NSWindow) -> Void)?
        private let shouldClose: (() -> Bool)?
        private let onWillClose: (() -> Void)?
        private weak var attachedWindow: NSWindow?

        init(
            onWindowAvailable: ((NSWindow) -> Void)?,
            shouldClose: (() -> Bool)?,
            onWillClose: (() -> Void)?
        ) {
            self.onWindowAvailable = onWindowAvailable
            self.shouldClose = shouldClose
            self.onWillClose = onWillClose
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            guard attachedWindow !== window else { return }
            attachedWindow?.delegate = nil
            attachedWindow = window
            window.delegate = self
            onWindowAvailable?(window)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            shouldClose?() ?? true
        }

        func windowWillClose(_ notification: Notification) {
            onWillClose?()
        }
    }
}
#endif

