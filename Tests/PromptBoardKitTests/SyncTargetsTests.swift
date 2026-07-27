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

    @Test func temporaryTargetsAreDistinctAndRootedUnderTheSystemTemporaryDirectory() {
        let targets = SyncTargets.temporary()
        #expect(targets.claudeSkillsURL != targets.agentsSkillsURL)
        let tmpDirectory = NSTemporaryDirectory()
        #expect(targets.claudeSkillsURL.path.hasPrefix(tmpDirectory))
        #expect(targets.agentsSkillsURL.path.hasPrefix(tmpDirectory))
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

    @Test func whitespaceOnlyOverrideFallsBackInsteadOfProducingACwdRelativePath() {
        let targets = SyncTargets.systemDefault(environment: [
            "PROMPTBOARD_CLAUDE_SKILLS_DIR": "   ",
            "PROMPTBOARD_AGENTS_SKILLS_DIR": "/tmp/a",
        ])
        #expect(targets.claudeSkillsURL.path.hasSuffix("/.claude/skills"))
        #expect(targets.agentsSkillsURL.path == "/tmp/a")
    }

    @Test func relativeOverrideFallsBackRatherThanResolvingAgainstTheWorkingDirectory() {
        let targets = SyncTargets.systemDefault(environment: [
            "PROMPTBOARD_CLAUDE_SKILLS_DIR": "relative/path",
            "PROMPTBOARD_AGENTS_SKILLS_DIR": "/tmp/a",
        ])
        #expect(targets.claudeSkillsURL.path.hasSuffix("/.claude/skills"))
        #expect(targets.agentsSkillsURL.path == "/tmp/a")
    }

    @Test func overrideWithSurroundingWhitespaceIsTrimmedAndHonoured() {
        let targets = SyncTargets.systemDefault(environment: [
            "PROMPTBOARD_CLAUDE_SKILLS_DIR": "  /tmp/c  ",
            "PROMPTBOARD_AGENTS_SKILLS_DIR": "/tmp/a",
        ])
        #expect(targets.claudeSkillsURL.path == "/tmp/c")
        #expect(targets.agentsSkillsURL.path == "/tmp/a")
    }

    @Test func tildeOverrideExpandsUnderTheHomeDirectoryAndIsHonoured() {
        let targets = SyncTargets.systemDefault(environment: [
            "PROMPTBOARD_CLAUDE_SKILLS_DIR": "~/tmp/iso",
            "PROMPTBOARD_AGENTS_SKILLS_DIR": "/tmp/a",
        ])
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(targets.claudeSkillsURL.path == home.appendingPathComponent("tmp/iso").path)
    }

    // Not every leading ~ resolves: an unknown user leaves the path untouched, so it's
    // still relative after expansion and must fall back the same as a plain relative
    // path — the warning this logs is enough; we don't assert on stderr here.
    @Test func overrideStillRelativeAfterTildeExpansionFallsBack() {
        let targets = SyncTargets.systemDefault(environment: [
            "PROMPTBOARD_CLAUDE_SKILLS_DIR": "~doesnotexist12345/skills",
            "PROMPTBOARD_AGENTS_SKILLS_DIR": "/tmp/a",
        ])
        #expect(targets.claudeSkillsURL.path.hasSuffix("/.claude/skills"))
        #expect(targets.agentsSkillsURL.path == "/tmp/a")
    }
}
