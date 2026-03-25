//
//  SymbolicationService.swift
//  SymPro
//

import Foundation
import DWARF
import DWARFSymbolication

/// In-process symbolication: no external Process (symbolicatecrash/atos).
final class SymbolicationService {
    private let queue = DispatchQueue(label: "com.sympro.symbolication", qos: .userInitiated)

    struct Output {
        let text: String
        let model: CrashReportModel?
    }

    private func normalizeUUIDString(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = UUID(uuidString: trimmed) { return u.uuidString }

        // 兼容 iOS 导出/三方导出：有些 uuid 可能是 32 位纯 hex（无短横线）。
        let compact = trimmed.replacingOccurrences(of: "-", with: "").uppercased()
        guard compact.count == 32, compact.allSatisfy({ $0.isHexDigit }) else { return nil }

        let formatted =
            "\(compact.prefix(8))-" +
            "\(compact.dropFirst(8).prefix(4))-" +
            "\(compact.dropFirst(12).prefix(4))-" +
            "\(compact.dropFirst(16).prefix(4))-" +
            "\(compact.suffix(12))"
        return UUID(uuidString: formatted)?.uuidString ?? formatted
    }

    private func fmtHex(_ n: UInt64) -> String {
        String(format: "0x%016llx", n)
    }

    /// Reads Mach-O __TEXT segment vmaddr from a (fat/thin) Mach-O binary.
    /// This is used to "unslide" runtime addresses: \(unslid = textVMAddr + imageOffset\).
    private func readTextVMAddr(fromMachO url: URL) -> UInt64? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let bytes = [UInt8](data)
        guard bytes.count >= 32 else { return nil }

        func readU32(_ at: Int, big: Bool) -> UInt32 {
            guard at + 4 <= bytes.count else { return 0 }
            if big {
                return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
            } else {
                return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            }
        }
        func readU64(_ at: Int, big: Bool) -> UInt64 {
            let hi = UInt64(readU32(at, big: big))
            let lo = UInt64(readU32(at + 4, big: big))
            return big ? ((hi << 32) | lo) : (hi | (lo << 32))
        }

        let magicLE = readU32(0, big: false)
        let magicBE = readU32(0, big: true)

        let FAT_MAGIC: UInt32 = 0xCAFEBABE
        let FAT_CIGAM: UInt32 = 0xBEBAFECA
        if magicBE == FAT_MAGIC || magicBE == FAT_CIGAM || magicLE == FAT_MAGIC || magicLE == FAT_CIGAM {
            let fatBig = (magicBE == FAT_MAGIC) || (magicLE == FAT_CIGAM)
            let nfat = min(Int(readU32(4, big: fatBig)), 64)
            var archOffset = 8
            for _ in 0..<nfat {
                guard archOffset + 20 <= bytes.count else { break }
                let off = Int(readU32(archOffset + 8, big: fatBig))
                if let vm = readTextVMAddrAt(bytes: bytes, offset: off) { return vm }
                archOffset += 20
            }
            return nil
        }

        return readTextVMAddrAt(bytes: bytes, offset: 0)
    }

    private func readTextVMAddrAt(bytes: [UInt8], offset: Int) -> UInt64? {
        func readU32(_ at: Int, big: Bool) -> UInt32 {
            guard at + 4 <= bytes.count else { return 0 }
            if big {
                return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
            } else {
                return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            }
        }
        func readU64(_ at: Int, big: Bool) -> UInt64 {
            let hi = UInt64(readU32(at, big: big))
            let lo = UInt64(readU32(at + 4, big: big))
            return big ? ((hi << 32) | lo) : (hi | (lo << 32))
        }

        guard offset + 32 <= bytes.count else { return nil }
        let magicLE = readU32(offset + 0, big: false)
        let magicBE = readU32(offset + 0, big: true)
        let MH_MAGIC_64: UInt32 = 0xFEEDFACF
        let MH_CIGAM_64: UInt32 = 0xCFFAEDFE
        let MH_MAGIC: UInt32 = 0xFEEDFACE
        let MH_CIGAM: UInt32 = 0xCEFAEDFE

        let big: Bool
        let is64: Bool
        if magicLE == MH_MAGIC_64 { big = false; is64 = true }
        else if magicBE == MH_MAGIC_64 { big = true; is64 = true }
        else if magicLE == MH_CIGAM_64 { big = true; is64 = true }
        else if magicLE == MH_MAGIC { big = false; is64 = false }
        else if magicBE == MH_MAGIC { big = true; is64 = false }
        else if magicLE == MH_CIGAM { big = true; is64 = false }
        else { return nil }

        let headerSize = is64 ? 32 : 28
        let ncmds = Int(readU32(offset + 16, big: big))
        let maxNcmds = min(ncmds, 4096)
        var lcOffset = offset + headerSize

        let LC_SEGMENT: UInt32 = 0x1
        let LC_SEGMENT_64: UInt32 = 0x19

        for _ in 0..<maxNcmds {
            guard lcOffset + 8 <= bytes.count else { break }
            let cmd = readU32(lcOffset + 0, big: big)
            let cmdsize = Int(readU32(lcOffset + 4, big: big))
            guard cmdsize >= 8, lcOffset + cmdsize <= bytes.count else { break }

            let isSeg = (is64 && cmd == LC_SEGMENT_64) || (!is64 && cmd == LC_SEGMENT)
            if isSeg {
                // segment_command_64: segname[16] at +8, vmaddr at +24 (u64)
                // segment_command:    segname[16] at +8, vmaddr at +24 (u32)
                let nameStart = lcOffset + 8
                let nameEnd = min(nameStart + 16, bytes.count)
                let nameBytes = bytes[nameStart..<nameEnd]
                let segname = String(bytes: nameBytes.prefix { $0 != 0 }, encoding: .utf8) ?? ""
                if segname == "__TEXT" {
                    if is64 {
                        return readU64(lcOffset + 24, big: big)
                    } else {
                        return UInt64(readU32(lcOffset + 24, big: big))
                    }
                }
            }
            lcOffset += cmdsize
        }
        return nil
    }

    func symbolicate(crashLog: CrashLog, dsymPaths: [URL]) async -> Result<Output, Error> {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .failure(SymbolicationError.cancelled))
                    return
                }
                let result = self.symbolicateSync(crashLog: crashLog, dsymPaths: dsymPaths)
                continuation.resume(returning: result)
            }
        }
    }

    /// 使用 swift-dwarf 对 .ips 的 threads/frames 做符号化，并生成新的 Translated Report 文本。
    /// - Note: `.crash` 文本暂不做逐行替换（仍返回 rawText）。
    private func symbolicateSync(crashLog: CrashLog, dsymPaths: [URL]) -> Result<Output, Error> {
        var diag: [String] = []
        func log(_ line: String) {
            diag.append(line)
            #if DEBUG
            print("[Symbolication] \(line)")
            #endif
        }

        log("start: file=\(crashLog.fileName), dsymPaths=\(dsymPaths.count)")
        guard !dsymPaths.isEmpty else {
            log("fail: dsymPaths is empty")
            return .failure(SymbolicationError.noMatchingDSYM)
        }

        // 仅处理 .ips：sourceText 第一行 metadata JSON，后续为 report JSON
        let lines = crashLog.sourceText.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first,
              let metaData = String(first).data(using: .utf8),
              var metadata = (try? JSONSerialization.jsonObject(with: metaData)) as? [String: Any]
        else {
            log("skip: not ips JSON (metadata parse failed). returning rawText")
            return .success(Output(text: crashLog.rawText, model: crashLog.model))
        }

        let rest = lines.dropFirst().joined(separator: "\n")
        var report: [String: Any]? = nil
        if let reportData = rest.data(using: .utf8),
           let parsed = (try? JSONSerialization.jsonObject(with: reportData)) as? [String: Any] {
            report = parsed
            log("ips JSON parsed: metadataKeys=\(metadata.count), reportKeys=\(parsed.count)")
        } else {
            log("skip: not ips JSON (report parse failed). will try text-based symbolication from model")
        }

        // 建立 UUID -> dSYM DWARF binary path 的快速映射，并缓存 DWARFSession
        // 支持输入：
        // - *.dSYM 包
        // - *.xcarchive（会自动展开 dSYMs/ 下的 *.dSYM）
        // - 直接指向 DWARF 二进制文件（无扩展名）
        var dwarfBinaryByUUID: [String: String] = [:]

        func tryMapDWARFBinary(_ dwarfBinary: URL, context: String) {
            guard let uuid = DSYMUUIDResolver.resolveUUID(at: dwarfBinary)?.uuidString else {
                log("map skip: cannot read UUID from binary (\(context)) -> \(dwarfBinary.lastPathComponent)")
                return
            }
            dwarfBinaryByUUID[uuid] = dwarfBinary.path
            log("binary mapped: \(uuid) -> \(dwarfBinary.lastPathComponent) (\(context))")
        }

        func tryMapDSYM(_ dsym: URL, context: String) {
            if let bin = findDWARFBinary(inDSYM: dsym) {
                tryMapDWARFBinary(bin, context: "dSYM:\(dsym.lastPathComponent) \(context)")
            } else {
                log("map skip: dSYM missing DWARF binary (\(context)) -> \(dsym.lastPathComponent)")
            }
        }

        for input in dsymPaths {
            let ext = input.pathExtension.lowercased()
            if ext == "xcarchive" {
                let dsymsDir = input.appendingPathComponent("dSYMs", isDirectory: true)
                let list = (try? FileManager.default.contentsOfDirectory(at: dsymsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                if list.isEmpty {
                    log("map skip: xcarchive has no dSYMs/ entries -> \(input.lastPathComponent)")
                }
                for dsym in list where dsym.pathExtension.lowercased() == "dsym" {
                    tryMapDSYM(dsym, context: "from xcarchive")
                }
            } else if ext == "dsym" {
                tryMapDSYM(input, context: "direct")
            } else {
                // 可能直接传了 DWARF 二进制（例如 .../Contents/Resources/DWARF/<app>）
                tryMapDWARFBinary(input, context: "direct binary")
            }
        }

        guard !dwarfBinaryByUUID.isEmpty else {
            log("fail: no DWARF binaries mapped from dsymPaths")
            return .failure(SymbolicationError.noMatchingDSYM)
        }

        var sessions: [String: DWARFSession] = [:]
        defer { sessions.values.forEach { $0.close() } }
        var textVMAddrByUUID: [String: UInt64] = [:]

        // 走两条路：
        // 1) structured JSON：threads + usedImages（现有逻辑）
        // 2) 文本 Translated Report：threads/usedImages 不在 JSON 里，则基于 crashLog.model + binaryImages 做符号化兜底
        if var jsonReport = report,
           let threads = jsonReport["threads"] as? [[String: Any]],
           let usedImages = jsonReport["usedImages"] as? [[String: Any]] {

            var mutableThreads = threads
            log("report arrays: threads=\(mutableThreads.count), usedImages=\(usedImages.count)")

            // UUID 命中检查：usedImages 里的 Mach-O UUID 与已导入 dSYM 的 Mach-O UUID 是否有交集
            let crashUUIDs: [String] = usedImages.compactMap { normalizeUUIDString($0["uuid"] as? String) }
            let crashUUIDSet = Set(crashUUIDs)
            let dsymUUIDSet = Set(dwarfBinaryByUUID.keys)
            let hit = crashUUIDSet.intersection(dsymUUIDSet)
            log("uuid check: crashImages=\(crashUUIDSet.count) dsymMapped=\(dsymUUIDSet.count) hit=\(hit.count)")
            if hit.isEmpty {
                let sampleCrash = crashUUIDs.prefix(5).joined(separator: ", ")
                let sampleDSYM = dsymUUIDSet.prefix(5).joined(separator: ", ")
                log("uuid mismatch: crashUUID(sample)=\(sampleCrash)")
                log("uuid mismatch: dsymUUID(sample)=\(sampleDSYM)")
                let details = diag.joined(separator: "\n")
                return .failure(SymbolicationError.uuidMismatch(details: details))
            }

            func imageBase(_ imageIndex: Int) -> UInt64 {
                guard imageIndex >= 0, imageIndex < usedImages.count else { return 0 }
                return (usedImages[imageIndex]["base"] as? NSNumber)?.uint64Value ?? 0
            }

            func imageUUID(_ imageIndex: Int) -> String? {
                guard imageIndex >= 0, imageIndex < usedImages.count else { return nil }
                let u = usedImages[imageIndex]["uuid"] as? String
                return normalizeUUIDString(u)
            }

            var totalFrames = 0
            var consideredFrames = 0
            var symbolicatedFrames = 0
            var missUUID = 0
            var missDSYMMap = 0
            var sessionInitFail = 0
            var nilSymbolicate = 0

            for tIndex in mutableThreads.indices {
                guard var frames = mutableThreads[tIndex]["frames"] as? [[String: Any]] else { continue }
                for fIndex in frames.indices {
                    totalFrames += 1
                    let imageIndex = frames[fIndex]["imageIndex"] as? Int ?? 0
                    let off = (frames[fIndex]["imageOffset"] as? NSNumber)?.intValue ?? 0
                    let base = imageBase(imageIndex)
                    let pc = base &+ UInt64(off)

                    guard let uuid = imageUUID(imageIndex) else { missUUID += 1; continue }
                    consideredFrames += 1
                    guard let dwarfPath = dwarfBinaryByUUID[uuid] else { missDSYMMap += 1; continue }

                    let session: DWARFSession
                    if let cached = sessions[uuid] {
                        session = cached
                    } else {
                        do {
                            // 通用：默认 slice=0；如果需要按 arch 精准选择，可后续增强
                            let s = try DWARFSession(path: dwarfPath)
                            sessions[uuid] = s
                            session = s
                            if let info = try? s.objectInfo() {
                                log("session open: uuid=\(uuid) arch=\(info.architecture) slice=\(info.universalBinaryIndex)/\(info.universalBinaryCount)")
                            } else {
                                log("session open: uuid=\(uuid)")
                            }
                            if let vm = readTextVMAddr(fromMachO: URL(fileURLWithPath: dwarfPath)) {
                                textVMAddrByUUID[uuid] = vm
                                log("__TEXT vmaddr: uuid=\(uuid) vmaddr=\(fmtHex(vm))")
                            } else {
                                log("__TEXT vmaddr: uuid=\(uuid) unreadable (will use runtime pc)")
                            }
                        } catch {
                            sessionInitFail += 1
                            log("session init failed: uuid=\(uuid) path=\(URL(fileURLWithPath: dwarfPath).lastPathComponent) err=\(error)")
                            continue
                        }
                    }

                    // 尝试用 unslid 地址（text vmaddr + imageOffset）。若取不到 vmaddr，则退回 runtime pc。
                    let addr: UInt64 = {
                        if let vm = textVMAddrByUUID[uuid] {
                            return vm &+ UInt64(off)
                        }
                        return pc
                    }()

                    do {
                        if let result = try session.symbolicate(address: addr) {
                            if let fn = result.functionName, !fn.isEmpty {
                                frames[fIndex]["symbol"] = fn
                                frames[fIndex]["symbolLocation"] = 0
                            }
                            if let file = result.file, !file.isEmpty, let line = result.line {
                                frames[fIndex]["source"] = [
                                    "file": file,
                                    "line": Int(line)
                                ]
                            }
                            if (result.functionName?.isEmpty == false) || (result.file?.isEmpty == false) {
                                symbolicatedFrames += 1
                            } else {
                                nilSymbolicate += 1
                            }
                        } else {
                            nilSymbolicate += 1
                            if nilSymbolicate <= 5 {
                                log("symbolicate nil: pc=\(fmtHex(pc)) addr=\(fmtHex(addr)) off=\(off) uuid=\(uuid)")
                            }
                        }
                    } catch {
                        if diag.count < 200 {
                            log("symbolicate error: pc=\(fmtHex(pc)) addr=\(fmtHex(addr)) off=\(off) uuid=\(uuid) err=\(error)")
                        }
                    }
                }
                mutableThreads[tIndex]["frames"] = frames
            }

            jsonReport["threads"] = mutableThreads
            log("done(JSON): totalFrames=\(totalFrames) considered=\(consideredFrames) symbolicated=\(symbolicatedFrames) missUUID=\(missUUID) missDSYMMap=\(missDSYMMap) sessionInitFail=\(sessionInitFail) nilResult=\(nilSymbolicate)")

            if symbolicatedFrames == 0 {
                let details = diag.joined(separator: "\n")
                return .failure(SymbolicationError.noSymbolsFound(details: details))
            }

            let translated = IPSReportFormatter.translatedReport(metadata: metadata, report: jsonReport) ?? crashLog.rawText
            let model = CrashReportModel.fromIPS(metadata: metadata, report: jsonReport)
            return .success(Output(text: translated, model: model))
        } else {
            // --- 文本 Translated Report 符号化兜底 ---
            guard var model = (crashLog.model ?? CrashReportModel.fromTranslatedReportText(crashLog.rawText, processNameFallback: crashLog.processName)) else {
                log("skip(text): no structured model available. returning rawText")
                return .success(Output(text: crashLog.rawText, model: crashLog.model))
            }
            guard !model.threads.isEmpty else {
                log("skip(text): no structured model available. returning rawText")
                return .success(Output(text: crashLog.rawText, model: crashLog.model))
            }

            // uuidByBase：用 Binary Images（loadAddress）把 frame 的 imageBase 映射到 uuid
            var uuidByBase: [UInt64: String] = [:]
            for img in crashLog.binaryImages {
                guard let u = img.uuid, !u.isEmpty,
                      let norm = normalizeUUIDString(u) else { continue }
                uuidByBase[img.loadAddress] = norm
            }
            guard !uuidByBase.isEmpty else {
                log("skip(text): binaryImages uuid mapping is empty. returning rawText")
                return .success(Output(text: crashLog.rawText, model: crashLog.model))
            }

            let dsymUUIDSet = Set(dwarfBinaryByUUID.keys)
            let crashUUIDSet: Set<String> = Set(model.threads.flatMap { t in
                t.frames.compactMap { f in
                    guard let base = f.imageBase else { return nil }
                    return uuidByBase[base]
                }
            })
            let hit = crashUUIDSet.intersection(dsymUUIDSet)
            log("uuid check(text): crashImages=\(crashUUIDSet.count) dsymMapped=\(dsymUUIDSet.count) hit=\(hit.count)")
            if hit.isEmpty {
                let sampleCrash = crashUUIDSet.prefix(5).joined(separator: ", ")
                let sampleDSYM = dsymUUIDSet.prefix(5).joined(separator: ", ")
                log("uuid mismatch(text): crashUUID(sample)=\(sampleCrash)")
                log("uuid mismatch(text): dsymUUID(sample)=\(sampleDSYM)")
                let details = diag.joined(separator: "\n")
                return .failure(SymbolicationError.uuidMismatch(details: details))
            }

            var totalFrames = 0
            var consideredFrames = 0
            var symbolicatedFrames = 0
            var missUUID = 0
            var missDSYMMap = 0
            var sessionInitFail = 0
            var nilSymbolicate = 0

            for tIndex in model.threads.indices {
                for fIndex in model.threads[tIndex].frames.indices {
                    totalFrames += 1
                    let frame = model.threads[tIndex].frames[fIndex]
                    guard let base = frame.imageBase,
                          let off = frame.imageOffset else { missUUID += 1; continue }

                    let uuid = uuidByBase[base] ?? ""
                    guard !uuid.isEmpty else { missUUID += 1; continue }
                    consideredFrames += 1
                    guard let dwarfPath = dwarfBinaryByUUID[uuid] else { missDSYMMap += 1; continue }

                    let session: DWARFSession
                    if let cached = sessions[uuid] {
                        session = cached
                    } else {
                        do {
                            let s = try DWARFSession(path: dwarfPath)
                            sessions[uuid] = s
                            session = s
                            if let vm = readTextVMAddr(fromMachO: URL(fileURLWithPath: dwarfPath)) {
                                textVMAddrByUUID[uuid] = vm
                            }
                        } catch {
                            sessionInitFail += 1
                            log("session init failed(text): uuid=\(uuid) err=\(error)")
                            continue
                        }
                    }

                    let addr: UInt64 = {
                        if let vm = textVMAddrByUUID[uuid] {
                            let uoff = UInt64(max(off, 0))
                            return vm &+ uoff
                        }
                        return frame.address
                    }()

                    do {
                        if let result = try session.symbolicate(address: addr) {
                            if let fn = result.functionName, !fn.isEmpty {
                                model.threads[tIndex].frames[fIndex].symbol = fn
                                model.threads[tIndex].frames[fIndex].symbolLocation = 0
                            }
                            if let file = result.file, !file.isEmpty, let line = result.line {
                                model.threads[tIndex].frames[fIndex].sourceFile = file
                                model.threads[tIndex].frames[fIndex].sourceLine = Int(line)
                            }
                            if (result.functionName?.isEmpty == false) || (result.file?.isEmpty == false) {
                                symbolicatedFrames += 1
                            } else {
                                nilSymbolicate += 1
                            }
                        } else {
                            nilSymbolicate += 1
                            if nilSymbolicate <= 5 {
                                log("symbolicate nil(text): pc=\(fmtHex(frame.address)) addr=\(fmtHex(addr)) off=\(off) uuid=\(uuid)")
                            }
                        }
                    } catch {
                        if diag.count < 200 {
                            log("symbolicate error(text): pc=\(fmtHex(frame.address)) addr=\(fmtHex(addr)) off=\(off) uuid=\(uuid) err=\(error)")
                        }
                    }
                }
            }

            log("done(text): totalFrames=\(totalFrames) considered=\(consideredFrames) symbolicated=\(symbolicatedFrames) missUUID=\(missUUID) missDSYMMap=\(missDSYMMap) sessionInitFail=\(sessionInitFail) nilResult=\(nilSymbolicate)")

            if symbolicatedFrames == 0 {
                let details = diag.joined(separator: "\n")
                return .failure(SymbolicationError.noSymbolsFound(details: details))
            }

            // 文本版不再尝试重排/生成 Translated Report（那需要逐行替换），只返回可用于 UI 的结构化 model。
            return .success(Output(text: crashLog.rawText, model: model))
        }
    }

    /// dSYM bundle -> Contents/Resources/DWARF/<binary>
    private func findDWARFBinary(inDSYM dsym: URL) -> URL? {
        // 在 sandbox 下，直接枚举 .dSYM 包内部目录有时会失败（权限/包访问差异）。
        // 这里主动开启 security scope，并在结束后关闭。
        let needsScope = dsym.startAccessingSecurityScopedResource()
        defer { if needsScope { dsym.stopAccessingSecurityScopedResource() } }

        let dwarfDir = dsym
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("DWARF", isDirectory: true)

        do {
            let list = try FileManager.default.contentsOfDirectory(
                at: dwarfDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            // 绝大多数情况下只有一个二进制；取第一个即可（优先 regular file）
            if let firstFile = list.first(where: { ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false) }) {
                // 再对具体 binary 开启一次 scope（更稳，避免后续读文件失败）
                _ = firstFile.startAccessingSecurityScopedResource()
                return firstFile
            }
            if let first = list.first {
                _ = first.startAccessingSecurityScopedResource()
                return first
            }
            return nil
        } catch {
            #if DEBUG
            print("[Symbolication] findDWARFBinary failed: \(error.localizedDescription) dir=\(dwarfDir.path)")
            #endif
            return nil
        }
    }
}

enum SymbolicationError: LocalizedError {
    case cancelled
    case noMatchingDSYM
    case invalidAddress
    case uuidMismatch(details: String)
    case noSymbolsFound(details: String)

    enum Kind {
        case cancelled
        case noMatchingDSYM
        case invalidAddress
        case uuidMismatch
        case noSymbolsFound
    }

    var kind: Kind {
        switch self {
        case .cancelled: return .cancelled
        case .noMatchingDSYM: return .noMatchingDSYM
        case .invalidAddress: return .invalidAddress
        case .uuidMismatch: return .uuidMismatch
        case .noSymbolsFound: return .noSymbolsFound
        }
    }

    var errorDescription: String? {
        switch self {
        case .cancelled: return L10n.t("Cancelled")
        case .noMatchingDSYM: return L10n.t("No matching dSYM found")
        case .invalidAddress: return L10n.t("Invalid address")
        case .uuidMismatch(let details):
            return L10n.tFormat(
                "dSYM UUID does not match the crash image UUID.\n\nPlease make sure you selected dSYMs from the same build (the UUID must match).\n\n%@",
                details
            )
        case .noSymbolsFound(let details):
            return L10n.tFormat(
                "Failed to symbolicate any frames from the dSYM.\n\n%@",
                details
            )
        }
    }
}
