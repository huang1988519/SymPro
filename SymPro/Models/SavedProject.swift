//
//  SavedProject.swift
//  SymPro
//

import Foundation
import Combine
import SwiftUI

struct SavedProject: Identifiable, Codable {
    var id: UUID
    var crashPath: String
    var dsymPaths: [String]
    var createdAt: Date
    var crashFileName: String { (crashPath as NSString).lastPathComponent }
}

final class ProjectHistoryStore: NSObject, ObservableObject {
    static let shared = ProjectHistoryStore()
    private let key = "sympro.recentProjects"
    private let maxCount = 20

    @Published private(set) var projects: [SavedProject] = []

    override init() {
        super.init()
        load()
    }

    func add(crashPath: String, dsymPaths: [String]) {
        let project = SavedProject(
            id: UUID(),
            crashPath: crashPath,
            dsymPaths: dsymPaths,
            createdAt: Date()
        )
        projects.removeAll { $0.crashPath == crashPath && $0.dsymPaths == dsymPaths }
        projects.insert(project, at: 0)
        if projects.count > maxCount {
            projects = Array(projects.prefix(maxCount))
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >).filter({ $0 < projects.count }) {
            projects.remove(at: index)
        }
        save()
    }

    func removeAll() {
        projects = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedProject].self, from: data) else { return }
        projects = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
