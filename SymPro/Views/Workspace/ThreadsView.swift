//
//  ThreadsView.swift
//  SymPro
//

import SwiftUI

struct ThreadsView: View {
    @ObservedObject var state: SymbolicateWorkspaceState
    @State private var selectedThreadIndex: Int = 0
    @State private var frameScrollID: UUID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let model = (state.symbolicatedModel ?? state.crashLog?.model) {
                HStack(spacing: 0) {
                    threadList(model: model)
                    Divider()
                    threadDetail(model: model)
                }
            } else {
                Text("Structured Threads view is supported for .ips only (to be extended for .crash later).")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedThreadIndex) { _ in
            frameScrollID = UUID()
        }
    }

    private var header: some View {
         HStack {
             Text("Threads")
                 .font(.headline)
             Spacer()
         }
         .padding(.horizontal)
         .padding(.vertical, 10)
    }

    private func threadList(model: CrashReportModel) -> some View {
        let threads = model.threads.filter { !$0.frames.isEmpty }
        return Group {
            if #available(macOS 13.0, *) {
                List(selection: Binding(
                    get: { selectedThreadIndex },
                    set: { selectedThreadIndex = $0 }
                )) {
                    ForEach(threads) { t in
                        threadRow(t)
                        .tag(t.index)
                    }
                }
//                .listStyle(.sidebar)
            } else {
                List {
                    ForEach(threads) { t in
                        Button {
                            selectedThreadIndex = t.index
                        } label: {
                            threadRow(t)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedThreadIndex == t.index ? Color.accentColor.opacity(0.18) : Color.clear)
                    }
                }
//                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 150, idealWidth: 180, maxWidth: 220)
    }

    private func threadRow(_ t: CrashReportModel.Thread) -> some View {
        let previewText: String = {
            guard let top = t.frames.first else { return "" }
            let module = top.imageName
            let symbol = (top.symbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(module)\(symbol.isEmpty ? "" : " — \(symbol)")"
        }()
        let tooltip: String = {
            var parts: [String] = [L10n.tFormat("Thread %d", t.index)]
            if t.triggered { parts.append(L10n.t("Crashed")) }
            if !previewText.isEmpty { parts.append(previewText) }
            if let q = t.queue, !q.isEmpty { parts.append(L10n.tFormat("Queue: %@", q)) }
            return parts.joined(separator: "\n")
        }()

        return HStack(alignment: .center, spacing: 10) {
            // 1. 图标区：崩溃用红色实心，普通用灰色线性
            Image(systemName: t.triggered ? "exclamationmark.octagon.fill" : "cpu")
                .font(.system(size: 14))
                .foregroundStyle(t.triggered ? .red : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    // 2. 线程标题
                    Text(L10n.tFormat("Thread %d", t.index))
                        .font(.system(.body, design: .rounded))
                        .fontWeight(t.triggered ? .bold : .medium)
                    
                    // 3. 标签区：Crashed 标签应使用更醒目的语义颜色
                    if t.triggered {
                        Text("Crashed")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.15)))
                            .foregroundStyle(.red)
                    } else if t.index == 0 {
                        Text("Main")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                            .foregroundStyle(.secondary)
                    }
                }

                // 4. 副标题：优化预览文本，突出模块名
                if !previewText.isEmpty {
                    Text(previewText)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(.secondary.opacity(0.8))
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .help(tooltip)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private func threadDetail(model: CrashReportModel) -> some View {
        let threads = model.threads.filter { !$0.frames.isEmpty }
        let thread = threads.first(where: { $0.index == selectedThreadIndex }) ?? threads.first
        return VStack(spacing: 0) {
            if let t = thread {
//                HStack {
//                    Text(title(for: t))
//                        .font(.subheadline.weight(.semibold))
//                    Spacer()
//                }
//                .padding(.horizontal, 12)
//                .padding(.vertical, 10)
//
//                Divider()

                frameTable(thread: t, appName: state.crashLog?.processName)
            } else {
                Text("No thread data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func title(for t: CrashReportModel.Thread) -> String {
        var parts: [String] = ["Thread \(t.index)"]
        if t.triggered { parts.append("Crashed") }
        if let q = t.queue, !q.isEmpty { parts.append("Dispatch queue: \(q)") }
        return parts.joined(separator: " — ")
    }

    private func frameTable(thread: CrashReportModel.Thread, appName: String?) -> some View {
        let app = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let firstAppID = thread.frames.first(where: { !app.isEmpty && $0.imageName == app })?.id

        return Table(thread.frames) {
            TableColumn(thread.name ?? "---") { f in
//                let isCrash = f.index == 0
                let isFirstApp = f.id == firstAppID
                // 调用你之前的 frameRow，但去掉最外层的宽度限制
                frameRow(f, appName: app, isFirstAppFrame: isFirstApp)
                    .padding(.horizontal, -8) // 抵消 Table 默认的单元格内边距
            }
        }
        .tableStyle(.bordered)
        
    }

    private func frameRow(_ f: CrashReportModel.Frame, appName: String, isFirstAppFrame: Bool) -> some View {
        let isApp = !appName.isEmpty && f.imageName == appName
        let isCrashFrame = f.index == 0
        let addr = String(format: "0x%012llx", f.address) // 缩短一点显示长度更有美感
        
        // 处理符号显示：如果是 App 代码，加粗显示
        let symbolTitle: String = {
            if let s = f.symbol, !s.isEmpty { return s }
            return addr
        }()

        return HStack(alignment: .center, spacing: 12) {
            // 1. 图标状态
            frameIcon(kind: frameKind(frame: f, appName: appName))
                .frame(width: 20)

            // 2. 序号
            Text("\(f.index)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            // 3. 核心信息区
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // 函数名/符号名
                    Text(symbolTitle)
                        .font(.system(isApp ? .body : .subheadline, design: .monospaced))
                        .fontWeight(isApp ? .bold : .regular)
                        .foregroundStyle(isApp ? Color.primary : Color.primary.opacity(0.8))
                    
                    // 偏移量
                    if let loc = f.symbolLocation {
                        Text("+ \(loc)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    // 模块名
                    Text(f.imageName)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(isApp ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                        .cornerRadius(3)
                        .foregroundStyle(isApp ? .blue : .secondary)

                    // 内存地址
                    Text(addr)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        // 使用 background 代替 listRowBackground
        .background(
            ZStack {
                if isCrashFrame {
                    Color.red.opacity(0.12)
                } else if isFirstAppFrame {
                    Color.orange.opacity(0.08)
                } else if isApp {
                    Color.blue.opacity(0.03) // App 代码给个极淡的底色区分
                }
            }
        )
        // 增加一条极淡的分割线
        .overlay(
            Divider().opacity(0.5), alignment: .bottom
        )
    }

    private enum FrameKind {
        case app
        case swiftUI
        case system
        case other
    }

    private func frameKind(frame: CrashReportModel.Frame, appName: String) -> FrameKind {
        let img = frame.imageName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appName.isEmpty && img == appName { return .app }
        if img == "SwiftUI" { return .swiftUI }
        // 常见系统镜像名兜底（threads frame 没有 path）
        if img.hasPrefix("libsystem") || img.hasPrefix("libc++") || img == "dyld" { return .system }
        return .other
    }

    private func frameIcon(kind: FrameKind) -> some View {
        let (symbol, color): (String, Color) = {
            switch kind {
            case .app: return ("person.fill", Color.blue)
            case .swiftUI: return ("square.stack.3d.up.fill", Color.purple)
            case .system: return ("gearshape.fill", Color(red: 0.63, green: 0.43, blue: 0.24))
            case .other: return ("chevron.left.forwardslash.chevron.right", Color.purple)
            }
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }
}

#Preview {
    ThreadsView(state: SymbolicateWorkspaceState())
        .frame(width: 1100, height: 700)
}

