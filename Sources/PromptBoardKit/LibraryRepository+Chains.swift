import Foundation

// Chains share the prompts tree and the slug namespace, so they reuse its
// helpers; only the frontmatter `kind: chain` tells them apart.
extension LibraryRepository {
    @discardableResult
    public func addChain(title: String, steps: [Chain.Step], group: String? = nil) throws -> Chain {
        try withExclusiveLock {
            let destDir = try folderURL(for: .chain, path: group)
            try ensureDirectory(destDir)
            let normalized = Self.normalizedTitle(title)
            let slug = Slug.unique(Slug.make(from: normalized), existing: existingPromptSlugs())
            let chain = Chain(title: normalized, steps: steps, group: group)
            try writeChain(chain, to: destDir.appendingPathComponent("\(slug).md"))
            return chain
        }
    }

    @discardableResult
    public func updateChain(id: UUID, title: String, steps: [Chain.Step]) throws -> Chain {
        try withExclusiveLock {
            guard let found = try findChainFile(id: id) else {
                throw LibraryRepositoryError.chainNotFound(id)
            }
            var chain = found.chain
            chain.title = Self.normalizedTitle(title)
            chain.steps = steps
            chain.updatedAt = Date()
            try writeChain(chain, to: found.url)
            return chain
        }
    }

    @discardableResult
    public func deleteChain(id: UUID) throws -> Chain {
        try withExclusiveLock {
            guard let found = try findChainFile(id: id) else {
                throw LibraryRepositoryError.chainNotFound(id)
            }
            do {
                try FileManager.default.removeItem(at: found.url)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            return found.chain
        }
    }

    public func moveChain(id: UUID, toFolder folder: String?) throws {
        try withExclusiveLock {
            guard let found = try findChainFile(id: id) else {
                throw LibraryRepositoryError.chainNotFound(id)
            }
            _ = try relocatePromptFile(at: found.url, toFolder: folder)
        }
    }

    func findChainFile(id: UUID) throws -> (url: URL, chain: Chain)? {
        for url in promptFileURLs() {
            if let chain = readChain(at: url), chain.id == id {
                return (url, chain)
            }
        }
        return nil
    }
}
