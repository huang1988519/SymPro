//
//  ReportTextScrollView.swift
//  SymPro
//

import SwiftUI
import AppKit

struct ReportTextScrollView: NSViewRepresentable {
    let attributedText: NSAttributedString
    var minContentWidth: CGFloat = 1400

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        // documentView 需要有非零 frame，否则初始可能显示为空白
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        if let container = textView.textContainer {
            container.widthTracksTextView = false
            container.heightTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(attributedText)

        scrollView.documentView = textView
        // 初次就计算一次内容尺寸，确保可见
        DispatchQueue.main.async {
            updateTextViewSize(scrollView: scrollView, textView: textView, minContentWidth: minContentWidth, attributedText: attributedText)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(attributedText)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        updateTextViewSize(scrollView: nsView, textView: textView, minContentWidth: minContentWidth, attributedText: attributedText)
    }

    private func updateTextViewSize(scrollView: NSScrollView, textView: NSTextView, minContentWidth: CGFloat, attributedText: NSAttributedString) {
        // 不依赖 layoutManager 的 usedRect（在 SwiftUI 初始布局/未上屏阶段可能为 0）
        // 直接用 attributedText 计算内容尺寸，保证 documentView 非 0，从而避免空白。
        let used = attributedText.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let inset = textView.textContainerInset
        let w = max(minContentWidth, used.width + inset.width * 2)
        let minH: CGFloat = 600
        let h = max(minH, used.height + inset.height * 2)
        if textView.frame.size.width != w || textView.frame.size.height != h {
            textView.setFrameSize(NSSize(width: w, height: h))
        }
    }
}

