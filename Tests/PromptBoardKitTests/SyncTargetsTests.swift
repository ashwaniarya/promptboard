import Foundation
import Testing
@testable import PromptBoardKit

struct SyncTargetsTests {
    @Test func agentsDirectoryComesFirstSoCodexCursorOpenCodeAreCoveredFirst() {
        let targets = SyncTargets(
            claudeSkillsURL: URL(fileURLWithPath: "/tmp/claude"),
            agentsSkillsURL: URL(fileURLWithPath: "/tmp/agents")
        )
        #expect(targets.all.map(\.lastPathComponent) == ["agents", "claude"])
    }

    @Test func systemDefaultsPointAtTheTwoCoveringDirectories() {
        let targets = SyncTargets.systemDefault(environment: [:])
        #expect(targets.claudeSkillsURL.path.hasSuffix("/.claude/skills"))
        #expect(targets.agentsSkillsURL.path.hasSuffix("/.agents/skills"))
    }

    @Test func environmentOverridesReplaceEitherDirectory() {
        let targets = SyncTargets.systemDefault(environment: [
            "PROMPTBOARD_CLAUDE_SKILLS_DIR": "/tmp/c",
            "PROMPTBOARD_AGENTS_SKILLS_DIR": "/tmp/a",
        ])
        #expect(targets.claudeSkillsURL.path == "/tmp/c")
        #expect(targets.agentsSkillsURL.path == "/tmp/a")
    }

    @Test func temporaryTargetsAreDistinctAndOutsideTheHomeDirectory() {
        let targets = SyncTargets.temporary()
        #expect(targets.claudeSkillsURL != targets.agentsSkillsURL)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(!targets.claudeSkillsURL.path.hasPrefix(home + "/.claude"))
        #expect(!targets.agentsSkillsURL.path.hasPrefix(home + "/.agents"))
    }

    @Test func repeatedTemporaryCallsProduceFreshRootsSoParallelTestsCannotCollide() {
        let first = SyncTargets.temporary()
        let second = SyncTargets.temporary()
        #expect(first.claudeSkillsURL != second.claudeSkillsURL)
        #expect(first.agentsSkillsURL != second.agentsSkillsURL)
    }

    @Test func emptyOverrideFallsBackWhileTheOtherOverrideStillApplies() {
        let targets = SyncTargets.systemDefault(environment: [
            "PROMPTBOARD_CLAUDE_SKILLS_DIR": "",
            "PROMPTBOARD_AGENTS_SKILLS_DIR": "/tmp/a",
        ])
        #expect(targets.claudeSkillsURL.path.hasSuffix("/.claude/skills"))
        #expect(targets.agentsSkillsURL.path == "/tmp/a")
    }

    @Test func systemDefaultsAreRootedExactlyAtTheHomeDirectory() {
        let targets = SyncTargets.systemDefault(environment: [:])
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(targets.claudeSkillsURL == home.appendingPathComponent(".claude/skills", isDirectory: true))
        #expect(targets.agentsSkillsURL == home.appendingPathComponent(".agents/skills", isDirectory: true))
    }
}
