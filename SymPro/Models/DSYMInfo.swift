//
//  DSYMInfo.swift
//  SymPro
//

import Foundation
import AppKit

struct DSYMInfo: Identifiable {
    let id: UUID
    let path: URL
    let displayName: String
    /// UUID from dSYM (Mach-O LC_UUID). Filled by parsing or dwarfdump; nil until resolved.
    var uuid: UUID?
    /// Architectures present in the dSYM (e.g. ["arm64", "x86_64"]).
    var architectures: [String] = []

    init(id: UUID = UUID(), path: URL, displayName: String, uuid: UUID? = nil, architectures: [String] = []) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.uuid = uuid
        self.architectures = architectures
    }
}

/// Resolves UUID (and optionally architectures) from a dSYM or binary path.
enum DSYMUUIDResolver {
    /// Reads UUID from dSYM using system tools when available, or simple Mach-O parse.
    /// Prefer in-process parsing for App Store sandbox.
    static func resolveUUID(at path: URL) -> UUID? {
        if path.pathExtension == "dSYM" {
            let contents = path.appendingPathComponent("Contents/Resources/DWARF")
            guard let firstBinary = try? FileManager.default.contentsOfDirectory(at: contents, includingPropertiesForKeys: nil).first else {
                return readUUIDFromMachO(at: path)
            }
            return readUUIDFromMachO(at: firstBinary)
        }
        return readUUIDFromMachO(at: path)
    }

    /// Minimal Mach-O LC_UUID reader (no external process). Supports thin and fat.
    private static func readUUIDFromMachO(at url: URL) -> UUID? {
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

        let magicLE = readU32(0, big: false)
        let magicBE = readU32(0, big: true)

        // FAT header (always big endian on disk for FAT_MAGIC, little for FAT_CIGAM)
        let FAT_MAGIC: UInt32 = 0xCAFEBABE
        let FAT_CIGAM: UInt32 = 0xBEBAFECA
        if magicBE == FAT_MAGIC || magicBE == FAT_CIGAM || magicLE == FAT_MAGIC || magicLE == FAT_CIGAM {
            let fatBig = (magicBE == FAT_MAGIC) || (magicLE == FAT_CIGAM)
            let nfat = min(Int(readU32(4, big: fatBig)), 64)
            var archOffset = 8
            for _ in 0..<nfat {
                // fat_arch: cputype(4) cpusubtype(4) offset(4) size(4) align(4)
                guard archOffset + 20 <= bytes.count else { break }
                let off = Int(readU32(archOffset + 8, big: fatBig))
                if let uuid = readUUIDAt(bytes: bytes, offset: off) {
                    return uuid
                }
                archOffset += 20
            }
            return nil
        }

        return readUUIDAt(bytes: bytes, offset: 0)
    }

    private static func readUUIDAt(bytes: [UInt8], offset: Int) -> UUID? {
        func readU32(_ at: Int, big: Bool) -> UInt32 {
            guard at + 4 <= bytes.count else { return 0 }
            if big {
                return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
            } else {
                return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            }
        }

        // Mach-O thin header
        guard offset + 32 <= bytes.count else { return nil }
        let magicLE = readU32(offset + 0, big: false)
        let magicBE = readU32(offset + 0, big: true)
        let MH_MAGIC: UInt32 = 0xFEEDFACE
        let MH_CIGAM: UInt32 = 0xCEFAEDFE
        let MH_MAGIC_64: UInt32 = 0xFEEDFACF
        let MH_CIGAM_64: UInt32 = 0xCFFAEDFE

        let big: Bool
        let is64: Bool
        if magicLE == MH_MAGIC {
            big = false; is64 = false
        } else if magicBE == MH_MAGIC {
            big = true; is64 = false
        } else if magicLE == MH_CIGAM {
            big = true; is64 = false
        } else if magicLE == MH_MAGIC_64 {
            big = false; is64 = true
        } else if magicBE == MH_MAGIC_64 {
            big = true; is64 = true
        } else if magicLE == MH_CIGAM_64 {
            big = true; is64 = true
        } else {
            return nil
        }

        let headerSize = is64 ? 32 : 28
        let ncmds = Int(readU32(offset + 16, big: big))
        let maxNcmds = min(ncmds, 4096)
        var lcOffset = offset + headerSize

        for _ in 0..<maxNcmds {
            guard lcOffset + 8 <= bytes.count else { break }
            let cmd = readU32(lcOffset + 0, big: big)
            let cmdsize = Int(readU32(lcOffset + 4, big: big))
            guard cmdsize >= 8, lcOffset + cmdsize <= bytes.count else { break }
            if cmd == 0x1B { // LC_UUID
                guard cmdsize >= 24, lcOffset + 24 <= bytes.count else { break }
                let u = Array(bytes[(lcOffset + 8)..<(lcOffset + 24)])
                return UUID(uuid: (u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7], u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]))
            }
            lcOffset += cmdsize
        }
        return nil
    }
}
