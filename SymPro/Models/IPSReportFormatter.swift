//
//  IPSReportFormatter.swift
//  SymPro
//
//  将 .ips 的 JSON 报告转换为苹果「Translated Report」人类可读格式。
//

import Foundation

enum IPSReportFormatter {
    /// 将 IPS 元数据（第一行）与报告 JSON 转为苹果 Translated Report 文本。
    static func translatedReport(metadata: [String: Any], report: [String: Any]) -> String? {
        guard (metadata["bug_type"] as? String) == "309" else { return nil }
        var lines: [String] = []
        // Process, Path, Identifier, Version, Code Type, Role, Parent, Coalition, User ID
        let procName = report["procName"] as? String ?? metadata["name"] as? String ?? "???"
        let pid = report["pid"] as? Int ?? 0
        lines.append("Process:             \(procName) [\(pid)]")
        let procPath = report["procPath"] as? String ?? ""
        lines.append("Path:                \(procPath)")
        let bundleInfo = report["bundleInfo"] as? [String: Any]
        let identifier = bundleInfo?["CFBundleIdentifier"] as? String ?? metadata["bundleID"] as? String ?? ""
        lines.append("Identifier:          \(identifier)")
        let shortVer = bundleInfo?["CFBundleShortVersionString"] as? String ?? metadata["app_version"] as? String ?? ""
        let buildVer = bundleInfo?["CFBundleVersion"] as? String ?? metadata["build_version"] as? String ?? ""
        lines.append("Version:             \(shortVer.isEmpty ? buildVer : "\(shortVer) (\(buildVer))")")
        let cpuType = report["cpuType"] as? String ?? "ARM-64"
        lines.append("Code Type:           \(cpuType) (Native)")
        let procRole = report["procRole"] as? String ?? ""
        lines.append("Role:                \(procRole)")
        let parentProc = report["parentProc"] as? String ?? ""
        let parentPid = report["parentPid"] as? Int ?? 0
        lines.append("Parent Process:      \(parentProc) [\(parentPid)]")
        let coalitionName = report["coalitionName"] as? String ?? ""
        let coalitionID = report["coalitionID"] as? Int ?? 0
        lines.append("Coalition:           \(coalitionName) [\(coalitionID)]")
        let userID = report["userID"] as? Int ?? 0
        lines.append("User ID:             \(userID)")
        lines.append("")

        // Date/Time, Launch Time, Hardware Model, OS Version, Release Type
        let captureTime = report["captureTime"] as? String ?? ""
        lines.append("Date/Time:           \(captureTime)")
        let procLaunch = report["procLaunch"] as? String ?? ""
        lines.append("Launch Time:         \(procLaunch)")
        let modelCode = report["modelCode"] as? String ?? ""
        lines.append("Hardware Model:      \(modelCode)")
        let osVersion = report["osVersion"] as? [String: Any]
        let train = osVersion?["train"] as? String ?? ""
        let build = osVersion?["build"] as? String ?? ""
        lines.append("OS Version:          \(train.isEmpty ? (metadata["os_version"] as? String ?? "") : "\(train) (\(build))")")
        let releaseType = osVersion?["releaseType"] as? String ?? "User"
        lines.append("Release Type:        \(releaseType)")
        lines.append("")

        // Crash Reporter Key, Incident Identifier
        let crashReporterKey = report["crashReporterKey"] as? String ?? ""
        lines.append("Crash Reporter Key:  \(crashReporterKey)")
        let incident = report["incident"] as? String ?? metadata["incident_id"] as? String ?? ""
        lines.append("Incident Identifier: \(incident)")
        lines.append("")

        // Sleep/Wake UUID, Time Awake Since Boot, Time Since Wake
        let sleepWakeUUID = report["sleepWakeUUID"] as? String ?? ""
        if !sleepWakeUUID.isEmpty {
            lines.append("Sleep/Wake UUID:       \(sleepWakeUUID)")
            lines.append("")
        }
        let uptime = report["uptime"] as? Int ?? 0
        lines.append("Time Awake Since Boot: \(uptime) seconds")
        let wakeTime = report["wakeTime"] as? Int ?? 0
        lines.append("Time Since Wake:        \(wakeTime) seconds")
        lines.append("")

        // System Integrity Protection
        let sip = report["sip"] as? String ?? "enabled"
        lines.append("System Integrity Protection: \(sip)")
        lines.append("")

        // Triggered by Thread
        let faultingThread = report["faultingThread"] as? Int ?? 0
        let legacyInfo = report["legacyInfo"] as? [String: Any]
        let threadTriggered = legacyInfo?["threadTriggered"] as? [String: Any]
        let queue = threadTriggered?["queue"] as? String
        if let q = queue, !q.isEmpty {
            lines.append("Triggered by Thread: \(faultingThread), Dispatch Queue: \(q)")
        } else {
            lines.append("Triggered by Thread: \(faultingThread)")
        }
        lines.append("")

        // Exception Type, Exception Codes, Termination Reason, Terminating Process
        let exception = report["exception"] as? [String: Any]
        let excType = exception?["type"] as? String ?? ""
        let excSignal = exception?["signal"] as? String ?? ""
        lines.append("Exception Type:    \(excType) (\(excSignal))")
        let excCodes = exception?["codes"] as? String ?? ""
        lines.append("Exception Codes:   \(excCodes)")
        lines.append("")

        let termination = report["termination"] as? [String: Any]
        let termNamespace = termination?["namespace"] as? String ?? ""
        let termCode = termination?["code"] as? Int ?? 0
        let termIndicator = termination?["indicator"] as? String ?? ""
        lines.append("Termination Reason:  Namespace \(termNamespace), Code \(termCode), \(termIndicator)")
        let byProc = termination?["byProc"] as? String ?? ""
        let byPid = termination?["byPid"] as? Int ?? 0
        lines.append("Terminating Process: \(byProc) [\(byPid)]")
        lines.append("")
        lines.append("")

        // Threads
        guard let threads = report["threads"] as? [[String: Any]],
              let usedImages = report["usedImages"] as? [[String: Any]] else {
            return lines.joined(separator: "\n")
        }

        let imageNameByIndex = usedImages.enumerated().reduce(into: [Int: String]()) { r, e in
            r[e.offset] = (e.element["name"] as? String) ?? "???"
        }

        for (threadIndex, thread) in threads.enumerated() {
            let triggered = (thread["triggered"] as? Bool) == true
            let queueName = thread["queue"] as? String
            let header: String
            if triggered {
                header = "Thread \(threadIndex) Crashed::"
            } else {
                header = "Thread \(threadIndex)::"
            }
            if let q = queueName, !q.isEmpty {
                lines.append("\(header)  Dispatch queue: \(q)")
            } else {
                lines.append(header)
            }

            let frames = thread["frames"] as? [[String: Any]] ?? []
            for (frameIndex, frame) in frames.enumerated() {
                let imageIndex = frame["imageIndex"] as? Int ?? 0
                let imageOffset = (frame["imageOffset"] as? NSNumber)?.intValue ?? 0
                let imageBase = imageIndex < usedImages.count ? (usedImages[imageIndex]["base"] as? NSNumber)?.uint64Value ?? 0 : 0
                let pc = imageBase + UInt64(imageOffset)
                let imageName = imageNameByIndex[imageIndex] ?? "???"
                let symbol = frame["symbol"] as? String
                let symbolLocation = (frame["symbolLocation"] as? NSNumber)?.intValue

                let addrStr = hex(pc)
                let rest: String
                if let sym = symbol, !sym.isEmpty {
                    if let loc = symbolLocation {
                        rest = "\(sym) + \(loc)"
                    } else {
                        rest = sym
                    }
                } else {
                    let baseStr = hex(imageBase)
                    rest = "\(baseStr) + \(imageOffset)"
                }
                lines.append("\(frameIndex)   \(imageName.padding(toLength: 28, withPad: " ", startingAt: 0))\t\(addrStr)  \(rest)")
            }
            lines.append("")
        }

        // Thread state (faulting thread only)
        if faultingThread < threads.count,
           let threadState = threads[faultingThread]["threadState"] as? [String: Any] {
            lines.append("Thread \(faultingThread) crashed with ARM Thread State (64-bit):")
            if let xArr = threadState["x"] as? [[String: Any]] {
                for start in stride(from: 0, to: min(28, xArr.count), by: 4) {
                    let parts = (start..<min(start+4, min(28, xArr.count))).map { i in
                        let v = (xArr[i]["value"] as? NSNumber)?.uint64Value ?? 0
                        let label = i < 10 ? "   x\(i):" : "  x\(i):"
                        return "\(label) \(hex(v))"
                    }
                    lines.append("    " + parts.joined(separator: "  "))
                }
            }
            let reg = { (key: String) -> String in
                let v = (threadState[key] as? [String: Any])?["value"] as? NSNumber
                return v.map { hex($0.uint64Value) } ?? "0x0"
            }
            let x28Val = (threadState["x"] as? [[String: Any]]).flatMap { arr in
                arr.count > 28 ? (arr[28]["value"] as? NSNumber)?.uint64Value : nil
            } ?? 0
            lines.append("   x28: \(hex(x28Val))   fp: \(reg("fp"))   lr: \(reg("lr"))")
            lines.append("    sp: \(reg("sp"))   pc: \(reg("pc")) cpsr: \(reg("cpsr"))")
            let esrObj = threadState["esr"] as? [String: Any]
            let esrVal = (esrObj?["value"] as? NSNumber)?.uint64Value ?? 0
            let esrDesc = esrObj?["description"] as? String ?? ""
            lines.append("   far: \(reg("far"))  esr: \(hex(esrVal)) \(esrDesc)")
            lines.append("")
        }

        // Binary Images
        lines.append("Binary Images:")
        for img in usedImages {
            guard let base = (img["base"] as? NSNumber)?.uint64Value else { continue }
            let size = (img["size"] as? NSNumber)?.uint64Value ?? 0
            let end: UInt64 = size > 0 ? base + size - 1 : (base == 0 ? 0xFFFF_FFFF_FFFF_FFFF : base)
            var name = img["name"] as? String ?? "???"
            let uuid = img["uuid"] as? String ?? ""
            var path = img["path"] as? String ?? ""
            if base == 0 && size == 0 {
                name = "???"
                path = "???"
            }
            let shortVer = img["CFBundleShortVersionString"] as? String
            let versionPart = shortVer.map { " (\($0))" } ?? (name == "???" ? " (*)" : "")
            let uuidPart = uuid.isEmpty ? "" : " <\(uuid)>"
            lines.append("       \(hex(base)) -        \(hex(end)) \(name)\(versionPart)\(uuidPart) \(path)")
        }
        lines.append("")

        // External Modification Summary
        if let extMods = report["extMods"] as? [String: Any],
           let caller = extMods["caller"] as? [String: Any],
           let targeted = extMods["targeted"] as? [String: Any],
           let system = extMods["system"] as? [String: Any] {
            lines.append("External Modification Summary:")
            lines.append("  Calls made by other processes targeting this process:")
            lines.append("    task_for_pid: \(caller["task_for_pid"] as? Int ?? 0)")
            lines.append("    thread_create: \(caller["thread_create"] as? Int ?? 0)")
            lines.append("    thread_set_state: \(caller["thread_set_state"] as? Int ?? 0)")
            lines.append("  Calls made by this process:")
            lines.append("    task_for_pid: \(targeted["task_for_pid"] as? Int ?? 0)")
            lines.append("    thread_create: \(targeted["thread_create"] as? Int ?? 0)")
            lines.append("    thread_set_state: \(targeted["thread_set_state"] as? Int ?? 0)")
            lines.append("  Calls made by all processes on this machine:")
            lines.append("    task_for_pid: \(system["task_for_pid"] as? Int ?? 0)")
            lines.append("    thread_create: \(system["thread_create"] as? Int ?? 0)")
            lines.append("    thread_set_state: \(system["thread_set_state"] as? Int ?? 0)")
            lines.append("")
        }

        // VM Region Summary
        if let vmSummary = report["vmSummary"] as? String, !vmSummary.isEmpty {
            lines.append("VM Region Summary:")
            lines.append(vmSummary)
        }

        return lines.joined(separator: "\n")
    }

    private static func hex(_ n: UInt64) -> String {
        String(format: "0x%016llx", n)
    }
}
