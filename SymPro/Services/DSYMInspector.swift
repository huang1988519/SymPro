import Foundation
import DWARF
import DWARFSymbolication

enum DSYMInspector {
    struct MachOArchitecturesInfo: Equatable {
        var isFat: Bool
        var architectures: [String]
    }

    struct DWARFSectionsInfo: Equatable {
        var dwarfSegmentFound: Bool
        var sectionNames: [String] // e.g. "__debug_info"
    }

    struct DWARFSessionInfo: Equatable {
        var canOpen: Bool
        var architecture: String?
        var universalBinaryIndex: Int?
        var universalBinaryCount: Int?
        var errorText: String?
    }

    struct FileInfo: Equatable {
        var fileName: String
        var path: String
        var fileSize: UInt64?
        var modificationDate: Date?
        var uuid: String?
    }

    struct DSYMDetails: Equatable {
        var file: FileInfo
        var arch: MachOArchitecturesInfo
        var dwarfSections: DWARFSectionsInfo
        var session: DWARFSessionInfo
        var capabilities: Capabilities
    }

    struct Capabilities: Equatable {
        var hasDwarfSegment: Bool
        var hasDebugInfo: Bool
        var hasDebugLine: Bool
        var hasAppleAccelerators: Bool
        var hasAranges: Bool
        var hasAbbrev: Bool

        var summary: String {
            if !hasDwarfSegment { return L10n.t("No __DWARF found (may not be a usable dSYM)") }
            if hasDebugInfo && hasDebugLine { return L10n.t("Symbolication available: function name + file line number") }
            if hasDebugInfo { return L10n.t("Symbolication available: function name (missing line table)") }
            return L10n.t("Incomplete DWARF information")
        }
    }

    struct SampleSymbolication: Equatable, Identifiable {
        let id = UUID()
        let pc: UInt64
        let addrUsed: UInt64
        let function: String?
        let fileLine: String?
        let ok: Bool
    }

    struct SymbolicationResult: Equatable {
        let addr: UInt64
        let function: String?
        let file: String?
        let line: UInt64?
    }

    static func resolveDWARFBinaryURL(from url: URL) -> URL? {
        if url.pathExtension.lowercased() == "dsym" {
            let dwarfDir = url
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("DWARF", isDirectory: true)
            let list = (try? FileManager.default.contentsOfDirectory(at: dwarfDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
            if let firstFile = list.first(where: { ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false) }) {
                return firstFile
            }
            return list.first
        }
        return url
    }

    static func inspect(dsymURL: URL) -> DSYMDetails {
        let binaryURL = resolveDWARFBinaryURL(from: dsymURL) ?? dsymURL

        let rv = try? binaryURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .nameKey])
        let fileName = rv?.name ?? binaryURL.lastPathComponent
        let fileSize = rv?.fileSize.map { UInt64($0) }
        let mdate = rv?.contentModificationDate
        let uuid = DSYMUUIDResolver.resolveUUID(at: binaryURL)?.uuidString

        let file = FileInfo(
            fileName: fileName,
            path: binaryURL.path,
            fileSize: fileSize,
            modificationDate: mdate,
            uuid: uuid
        )

        let arch = readArchitectures(fromMachO: binaryURL)
        let dwarfSections = readDWARFSections(fromMachO: binaryURL)
        let session = readSessionInfo(fromDWARF: binaryURL)
        let capabilities = deriveCapabilities(from: dwarfSections)

        return DSYMDetails(file: file, arch: arch, dwarfSections: dwarfSections, session: session, capabilities: capabilities)
    }

    static func sampleSymbolicate(dsymURL: URL, pcs: [UInt64], imageOffsets: [Int?]) -> [SampleSymbolication] {
        let binaryURL = resolveDWARFBinaryURL(from: dsymURL) ?? dsymURL
        guard !pcs.isEmpty else { return [] }
        do {
            let session = try DWARFSession(path: binaryURL.path)
            defer { session.close() }

            let textVMAddr = readTextVMAddr(fromMachO: binaryURL)
            var out: [SampleSymbolication] = []
            for (idx, pc) in pcs.prefix(3).enumerated() {
                let off = idx < imageOffsets.count ? imageOffsets[idx] : nil
                let addr: UInt64 = {
                    if let vm = textVMAddr, let off { return vm &+ UInt64(off) }
                    return pc
                }()
                do {
                    if let r = try session.symbolicate(address: addr) {
                        let fn = r.functionName
                        let fl: String? = {
                            if let f = r.file, !f.isEmpty, let l = r.line { return "\(f):\(l)" }
                            return nil
                        }()
                        out.append(SampleSymbolication(pc: pc, addrUsed: addr, function: fn, fileLine: fl, ok: (fn?.isEmpty == false) || (fl?.isEmpty == false)))
                    } else {
                        out.append(SampleSymbolication(pc: pc, addrUsed: addr, function: nil, fileLine: nil, ok: false))
                    }
                } catch {
                    out.append(SampleSymbolication(pc: pc, addrUsed: addr, function: "error", fileLine: error.localizedDescription, ok: false))
                }
            }
            return out
        } catch {
            return pcs.prefix(3).map { pc in
                SampleSymbolication(pc: pc, addrUsed: pc, function: "session init failed", fileLine: error.localizedDescription, ok: false)
            }
        }
    }

    static func symbolicate(dsymURL: URL, address: UInt64) -> Result<SymbolicationResult, Error> {
        let binaryURL = resolveDWARFBinaryURL(from: dsymURL) ?? dsymURL
        do {
            let session = try DWARFSession(path: binaryURL.path)
            defer { session.close() }
            let r = try session.symbolicate(address: address)
            return .success(SymbolicationResult(
                addr: address,
                function: r?.functionName,
                file: r?.file,
                line: r?.line
            ))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Derivations

    private static func deriveCapabilities(from sections: DWARFSectionsInfo) -> Capabilities {
        let set = Set(sections.sectionNames)
        let hasApple = set.contains("__apple_names") || set.contains("__apple_types") || set.contains("__apple_namespac") || set.contains("__apple_objc")
        return Capabilities(
            hasDwarfSegment: sections.dwarfSegmentFound,
            hasDebugInfo: set.contains("__debug_info"),
            hasDebugLine: set.contains("__debug_line"),
            hasAppleAccelerators: hasApple,
            hasAranges: set.contains("__debug_aranges"),
            hasAbbrev: set.contains("__debug_abbrev")
        )
    }

    // MARK: - Mach-O (__TEXT vmaddr)

    private static func readTextVMAddr(fromMachO url: URL) -> UInt64? {
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
        func readCString(at start: Int, max: Int) -> String {
            guard start < bytes.count else { return "" }
            let end = min(start + max, bytes.count)
            return String(bytes: bytes[start..<end].prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }

        let offset = firstThinOffset(bytes: bytes) ?? 0
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
                let segname = readCString(at: lcOffset + 8, max: 16)
                if segname == "__TEXT" {
                    if is64 { return readU64(lcOffset + 24, big: big) }
                    return UInt64(readU32(lcOffset + 24, big: big))
                }
            }
            lcOffset += cmdsize
        }
        return nil
    }

    // MARK: - Mach-O (fat arch list)

    private static func readArchitectures(fromMachO url: URL) -> MachOArchitecturesInfo {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return MachOArchitecturesInfo(isFat: false, architectures: [])
        }
        let bytes = [UInt8](data)
        guard bytes.count >= 16 else { return MachOArchitecturesInfo(isFat: false, architectures: []) }

        func readU32(_ at: Int, big: Bool) -> UInt32 {
            guard at + 4 <= bytes.count else { return 0 }
            if big {
                return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
            } else {
                return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            }
        }
        func cpuTypeName(_ cpu: UInt32) -> String {
            // Only cover common types we see in iOS/macOS dSYM.
            let CPU_TYPE_X86_64: UInt32 = 0x01000007
            let CPU_TYPE_ARM64: UInt32 = 0x0100000C
            let CPU_TYPE_ARM64_32: UInt32 = 0x0200000C
            let CPU_TYPE_X86: UInt32 = 7
            let CPU_TYPE_ARM: UInt32 = 12
            switch cpu {
            case CPU_TYPE_ARM64: return "arm64"
            case CPU_TYPE_ARM64_32: return "arm64_32"
            case CPU_TYPE_X86_64: return "x86_64"
            case CPU_TYPE_X86: return "i386"
            case CPU_TYPE_ARM: return "arm"
            default: return String(format: "cpu(0x%08x)", cpu)
            }
        }

        let magicBE = readU32(0, big: true)
        let magicLE = readU32(0, big: false)
        let FAT_MAGIC: UInt32 = 0xCAFEBABE
        let FAT_CIGAM: UInt32 = 0xBEBAFECA
        let isFat = (magicBE == FAT_MAGIC) || (magicBE == FAT_CIGAM) || (magicLE == FAT_MAGIC) || (magicLE == FAT_CIGAM)
        if !isFat {
            // thin Mach-O: parse cputype from mach_header(_64)
            let offset = 0
            guard offset + 8 <= bytes.count else { return MachOArchitecturesInfo(isFat: false, architectures: []) }

            let magicLE2 = readU32(offset + 0, big: false)
            let magicBE2 = readU32(offset + 0, big: true)
            let MH_MAGIC: UInt32 = 0xFEEDFACE
            let MH_CIGAM: UInt32 = 0xCEFAEDFE
            let MH_MAGIC_64: UInt32 = 0xFEEDFACF
            let MH_CIGAM_64: UInt32 = 0xCFFAEDFE

            let big: Bool
            if magicLE2 == MH_MAGIC || magicLE2 == MH_MAGIC_64 { big = false }
            else if magicBE2 == MH_MAGIC || magicBE2 == MH_MAGIC_64 { big = true }
            else if magicLE2 == MH_CIGAM || magicLE2 == MH_CIGAM_64 { big = true }
            else { return MachOArchitecturesInfo(isFat: false, architectures: []) }

            let cputype = readU32(offset + 4, big: big)
            return MachOArchitecturesInfo(isFat: false, architectures: [cpuTypeName(cputype)])
        }

        let fatBig = (magicBE == FAT_MAGIC) || (magicLE == FAT_CIGAM)
        let nfat = min(Int(readU32(4, big: fatBig)), 64)
        var archOffset = 8
        var out: [String] = []
        for _ in 0..<nfat {
            guard archOffset + 20 <= bytes.count else { break }
            let cputype = readU32(archOffset + 0, big: fatBig)
            out.append(cpuTypeName(cputype))
            archOffset += 20
        }
        return MachOArchitecturesInfo(isFat: true, architectures: Array(Set(out)).sorted())
    }

    // MARK: - Mach-O (__DWARF sections)

    private static func readDWARFSections(fromMachO url: URL) -> DWARFSectionsInfo {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return DWARFSectionsInfo(dwarfSegmentFound: false, sectionNames: [])
        }
        let bytes = [UInt8](data)
        guard bytes.count >= 32 else { return DWARFSectionsInfo(dwarfSegmentFound: false, sectionNames: []) }

        func readU32(_ at: Int, big: Bool) -> UInt32 {
            guard at + 4 <= bytes.count else { return 0 }
            if big {
                return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
            } else {
                return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            }
        }

        // For section parsing we only inspect the first slice for now (good enough for UI).
        let offset = firstThinOffset(bytes: bytes) ?? 0
        guard offset + 32 <= bytes.count else { return DWARFSectionsInfo(dwarfSegmentFound: false, sectionNames: []) }

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
        else { return DWARFSectionsInfo(dwarfSegmentFound: false, sectionNames: []) }

        let headerSize = is64 ? 32 : 28
        let ncmds = Int(readU32(offset + 16, big: big))
        let maxNcmds = min(ncmds, 4096)
        var lcOffset = offset + headerSize

        let LC_SEGMENT: UInt32 = 0x1
        let LC_SEGMENT_64: UInt32 = 0x19
        var dwarfFound = false
        var sections: [String] = []

        func readCString(at start: Int, max: Int) -> String {
            guard start < bytes.count else { return "" }
            let end = min(start + max, bytes.count)
            return String(bytes: bytes[start..<end].prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }

        for _ in 0..<maxNcmds {
            guard lcOffset + 8 <= bytes.count else { break }
            let cmd = readU32(lcOffset + 0, big: big)
            let cmdsize = Int(readU32(lcOffset + 4, big: big))
            guard cmdsize >= 8, lcOffset + cmdsize <= bytes.count else { break }

            let isSeg = (is64 && cmd == LC_SEGMENT_64) || (!is64 && cmd == LC_SEGMENT)
            if isSeg {
                let segname = readCString(at: lcOffset + 8, max: 16)
                let nsects: Int = {
                    if is64 { return Int(readU32(lcOffset + 64, big: big)) }
                    return Int(readU32(lcOffset + 48, big: big))
                }()
                if segname == "__DWARF" {
                    dwarfFound = true
                    // section_64 size = 80, section size = 68
                    let sectionStart = lcOffset + (is64 ? 72 : 56)
                    let sectionSize = is64 ? 80 : 68
                    for i in 0..<min(nsects, 256) {
                        let off = sectionStart + i * sectionSize
                        guard off + 16 <= bytes.count else { break }
                        let sectname = readCString(at: off + 0, max: 16)
                        if !sectname.isEmpty { sections.append(sectname) }
                    }
                }
            }
            lcOffset += cmdsize
        }

        return DWARFSectionsInfo(dwarfSegmentFound: dwarfFound, sectionNames: Array(Set(sections)).sorted())
    }

    private static func firstThinOffset(bytes: [UInt8]) -> Int? {
        func readU32(_ at: Int, big: Bool) -> UInt32 {
            guard at + 4 <= bytes.count else { return 0 }
            if big {
                return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
            } else {
                return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            }
        }

        let magicBE = readU32(0, big: true)
        let magicLE = readU32(0, big: false)
        let FAT_MAGIC: UInt32 = 0xCAFEBABE
        let FAT_CIGAM: UInt32 = 0xBEBAFECA
        let isFat = (magicBE == FAT_MAGIC) || (magicBE == FAT_CIGAM) || (magicLE == FAT_MAGIC) || (magicLE == FAT_CIGAM)
        guard isFat else { return 0 }
        let fatBig = (magicBE == FAT_MAGIC) || (magicLE == FAT_CIGAM)
        let nfat = min(Int(readU32(4, big: fatBig)), 64)
        guard nfat > 0 else { return nil }
        let archOffset = 8
        guard archOffset + 20 <= bytes.count else { return nil }
        let off = Int(readU32(archOffset + 8, big: fatBig))
        return off
        return nil
    }

    // MARK: - swift-dwarf session info

    private static func readSessionInfo(fromDWARF dwarfBinaryURL: URL) -> DWARFSessionInfo {
        do {
            let session = try DWARFSession(path: dwarfBinaryURL.path)
            defer { session.close() }
            if let info = try? session.objectInfo() {
                return DWARFSessionInfo(
                    canOpen: true,
                    architecture: String(describing: info.architecture),
                    universalBinaryIndex: Int(info.universalBinaryIndex),
                    universalBinaryCount: Int(info.universalBinaryCount),
                    errorText: nil
                )
            }
            return DWARFSessionInfo(canOpen: true, architecture: nil, universalBinaryIndex: nil, universalBinaryCount: nil, errorText: nil)
        } catch {
            return DWARFSessionInfo(
                canOpen: false,
                architecture: nil,
                universalBinaryIndex: nil,
                universalBinaryCount: nil,
                errorText: error.localizedDescription
            )
        }
    }

    // Exposed for UI helpers (manual symbolication).
    static func readTextVMAddrForUI(dsymURL: URL) -> UInt64? {
        let binaryURL = resolveDWARFBinaryURL(from: dsymURL) ?? dsymURL
        return readTextVMAddr(fromMachO: binaryURL)
    }
}

