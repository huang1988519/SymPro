import SwiftUI
import AppKit

struct BacktraceTableView: NSViewRepresentable {
    struct Row: Identifiable, Equatable {
        let id: Int
        let indexText: String
        let libraryText: String
        let symbolText: String
        let tooltip: String
        let isApp: Bool
    }

    let rows: [Row]

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = NSColor.separatorColor
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.intercellSpacing = NSSize(width: 10, height: 0)
        tableView.rowHeight = 28
        tableView.selectionHighlightStyle = .regular

        let colIndex = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("index"))
        colIndex.title = "#"
        colIndex.minWidth = 52
        colIndex.width = 52
        colIndex.maxWidth = 80
        tableView.addTableColumn(colIndex)

        let colLib = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library"))
        colLib.title = L10n.t("LIBRARY")
        colLib.minWidth = 200
        colLib.width = 240
        colLib.maxWidth = 360
        tableView.addTableColumn(colLib)

        let colSymbol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("symbol"))
        colSymbol.title = L10n.t("SYMBOL / INSTRUCTION")
        colSymbol.minWidth = 420
        colSymbol.width = 820
        tableView.addTableColumn(colSymbol)

        let clip = NSClipView()
        clip.drawsBackground = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        // 尊重系统“自动隐藏滚动条”的设置
        scroll.autohidesScrollers = true
        scroll.contentView = clip
        scroll.documentView = tableView

        context.coordinator.attach(tableView: tableView)
        context.coordinator.rows = rows
        tableView.reloadData()

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.rows = rows
        if let tableView = context.coordinator.tableView {
            tableView.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rows: rows)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var rows: [Row]
        weak var tableView: NSTableView?
        init(rows: [Row]) { self.rows = rows }

        func attach(tableView: NSTableView) {
            self.tableView = tableView
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let v = ThemedRowView()
            v.isAlternate = (row % 2 == 1)
            return v
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0 && row < rows.count else { return nil }
            let item = rows[row]
            let id = tableColumn?.identifier.rawValue ?? ""
            let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(id), owner: nil) as? CenterVAlignedCellView)
                ?? {
                    let v = CenterVAlignedCellView(identifier: id)
                    return v
                }()

            cell.toolTip = item.tooltip

            switch id {
            case "index":
                cell.textField?.stringValue = item.indexText
                cell.textField?.alignment = .right
                cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                cell.textField?.textColor = NSColor.secondaryLabelColor
                cell.textField?.lineBreakMode = .byClipping
            case "library":
                cell.textField?.stringValue = item.libraryText
                cell.textField?.alignment = .left
                cell.textField?.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
                cell.textField?.textColor = item.isApp ? NSColor.systemOrange : NSColor.labelColor
                cell.textField?.lineBreakMode = .byTruncatingTail
            default:
                cell.textField?.stringValue = item.symbolText
                cell.textField?.alignment = .left
                cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                cell.textField?.textColor = item.isApp ? NSColor.systemOrange : NSColor.secondaryLabelColor
                cell.textField?.lineBreakMode = .byTruncatingMiddle
            }

            return cell
        }
    }
}

private final class ThemedRowView: NSTableRowView {
    var isAlternate: Bool = false

    override var isEmphasized: Bool {
        get { false }
        set { /* ignore */ }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        // 用系统语义色 + 轻微透明来做“斑马纹”，同时兼容浅色/深色
        let base = NSColor.controlBackgroundColor
        let color = base.withAlphaComponent(isAlternate ? 0.75 : 0.55)
        color.setFill()
        dirtyRect.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

private final class CenterVAlignedCellView: NSTableCellView {
    init(identifier: String) {
        super.init(frame: .zero)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)

        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.usesSingleLineMode = true
        tf.maximumNumberOfLines = 1
        tf.lineBreakMode = .byTruncatingMiddle

        addSubview(tf)
        self.textField = tf

        NSLayoutConstraint.activate([
            tf.centerYAnchor.constraint(equalTo: centerYAnchor),
            tf.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            tf.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

