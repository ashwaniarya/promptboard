import Foundation
import Testing
@testable import PromptBoardKit

struct LibraryModelTests {
    @Test func promptGroupDefaultsToNilAndIsOmittedFromJSON() throws {
        let prompt = Prompt(title: "t", content: "c")
        #expect(prompt.group == nil)
        let json = try #require(String(data: JSONEncoder().encode(prompt), encoding: .utf8))
        #expect(!json.contains("group"))
    }

    @Test func promptGroupEncodesWhenPresent() throws {
        let prompt = Prompt(title: "t", content: "c", group: "Coding")
        let json = try #require(String(data: JSONEncoder().encode(prompt), encoding: .utf8))
        #expect(json.contains("Coding"))
    }

    @Test func libraryItemPromptExposesSharedAccessors() {
        let prompt = Prompt(title: "Code review", content: "body", group: "Coding")
        let item = LibraryItem.prompt(prompt)
        #expect(item.id == prompt.id)
        #expect(item.title == "Code review")
        #expect(item.group == "Coding")
        #expect(item.updatedAt == prompt.updatedAt)
        #expect(item.kind == .prompt)
    }

    @Test func libraryItemSkillUsesNameAsTitle() {
        let skill = Skill(name: "trello-card-reader", description: "Read a Trello card", group: "Research")
        let item = LibraryItem.skill(skill)
        #expect(item.id == skill.id)
        #expect(item.title == "trello-card-reader")
        #expect(item.group == "Research")
        #expect(item.kind == .skill)
    }

    @Test func skillDefaultsAreSane() {
        let skill = Skill(name: "n", description: "d")
        #expect(skill.group == nil)
        #expect(skill.body == "")
        #expect(skill.files.isEmpty)
    }
}
