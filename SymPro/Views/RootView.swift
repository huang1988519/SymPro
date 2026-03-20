//
//  RootView.swift
//  SymPro
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RootView: View {
    @EnvironmentObject private var workspaceState: SymbolicateWorkspaceState

    var body: some View {
        CrashAnalyzerRootView()
#if os(macOS)
        .background(
            WindowCloseObserver {
                Task { @MainActor in
                    workspaceState.resetWorkspace()
                }
            }
        )
#endif
        .onReceive(NotificationCenter.default.publisher(for: .symProOpenRecentFile)) { notification in
            guard let url = notification.userInfo?["url"] as? URL else { return }
            workspaceState.openCrashLog(url)
        }
        .onDisappear {
            Task { @MainActor in
                workspaceState.resetWorkspace()
            }
        }
    }
}

#if os(macOS)
private struct WindowCloseObserver: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowCloseTrackingNSView()
        view.onClose = onClose
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowCloseTrackingNSView)?.onClose = onClose
    }
}

private final class WindowCloseTrackingNSView: NSView {
    var onClose: (() -> Void)?
    private var closeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachCloseObserver()
    }

    deinit {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
    }

    private func attachCloseObserver() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        guard let window else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onClose?()
        }
    }
}
#endif

#Preview {
    RootView()
}
