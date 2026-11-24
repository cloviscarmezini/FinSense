import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Gerencia atalhos globais de teclado (⌘+Shift+$ e ⌘+Option+Space) via Carbon
/// e apresenta um NSPanel flutuante estilo Spotlight/Raycast sobre qualquer aplicativo.
@MainActor
public final class GlobalHotKeyManager {
    public static let shared = GlobalHotKeyManager()

    private var hotKeyDollarRef: EventHotKeyRef?
    private var hotKeySpaceRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    private init() {}

    public func registerQuickAddHotKeys(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        unregister()

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let mgr = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    mgr.onTrigger?()
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )

        // 1) ⌘ + Shift + $ (Tecla 4 + cmdKey + shiftKey)
        let id1 = EventHotKeyID(signature: OSType(0x4653_5141), id: 1) // 'FSQA'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_4),
            UInt32(cmdKey | shiftKey),
            id1,
            GetApplicationEventTarget(),
            0,
            &hotKeyDollarRef
        )

        // 2) ⌘ + Option + Space
        let id2 = EventHotKeyID(signature: OSType(0x4653_5142), id: 2) // 'FSQB'
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | optionKey),
            id2,
            GetApplicationEventTarget(),
            0,
            &hotKeySpaceRef
        )
    }

    public func unregister() {
        if let ref = hotKeyDollarRef {
            UnregisterEventHotKey(ref)
            hotKeyDollarRef = nil
        }
        if let ref = hotKeySpaceRef {
            UnregisterEventHotKey(ref)
            hotKeySpaceRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}

public final class QuickAddFloatingPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
}

@MainActor
public final class QuickAddPanelController {
    public static let shared = QuickAddPanelController()
    private var panel: QuickAddFloatingPanel?

    private init() {}

    public func toggle<Content: View>(@ViewBuilder content: () -> Content) {
        if let panel, panel.isVisible {
            close()
        } else {
            show(content: content)
        }
    }

    public func show<Content: View>(@ViewBuilder content: () -> Content) {
        if panel == nil {
            let newPanel = QuickAddFloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 280),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newPanel.level = .floating
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.isMovableByWindowBackground = true
            newPanel.titleVisibility = .hidden
            newPanel.titlebarAppearsTransparent = true
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            self.panel = newPanel
        }

        guard let panel else { return }
        let hosting = NSHostingView(rootView: content())
        panel.contentView = hosting
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let vf = screen.visibleFrame
            let x = vf.midX - 320
            let y = vf.midY + 80
            panel.setFrame(NSRect(x: x, y: y, width: 640, height: 280), display: true)
        } else {
            panel.center()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func close() {
        panel?.orderOut(nil)
    }
}
