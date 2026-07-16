import ArgumentParser
import Foundation
import PromptBoardKit

struct MCP: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve the prompt library to AI agents over stdio MCP."
    )

    @OptionGroup var location: DataDirectoryOptions

    func run() throws {
        MCPStdioServer(repository: location.repository).run()
    }
}

// Newline-delimited JSON-RPC over stdio, tools capability only. Hand-rolled
// because the official Swift SDK needs a newer toolchain than this machine's.
// Stdout carries protocol frames exclusively — diagnostics must use stderr.
final class MCPStdioServer {
    private let repository: PromptRepository
    private let standardOutput = FileHandle.standardOutput

    init(repository: PromptRepository) {
        self.repository = repository
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            let message = line.trimmingCharacters(in: .whitespaces)
            guard !message.isEmpty else { continue }
            handle(rawMessage: message)
        }
    }

    private func handle(rawMessage: String) {
        guard let message = try? JSONSerialization.jsonObject(with: Data(rawMessage.utf8)) as? [String: Any] else {
            send(errorResponse(id: NSNull(), code: -32700, message: "parse error"))
            return
        }
        guard let method = message["method"] as? String else { return }
        let requestID = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            send(response(id: requestID, result: initializeResult(params: params)))
        case "ping":
            send(response(id: requestID, result: [String: Any]()))
        case "tools/list":
            send(response(id: requestID, result: ["tools": PromptToolbox.toolDefinitions]))
        case "tools/call":
            handleToolCall(id: requestID, params: params)
        default:
            guard requestID != nil else { return }
            send(errorResponse(id: requestID ?? NSNull(), code: -32601, message: "method not found: \(method)"))
        }
    }

    private func initializeResult(params: [String: Any]) -> [String: Any] {
        // The tools-only surface is identical across spec revisions, so accept
        // whatever version the client leads with rather than forcing a downgrade
        let requestedVersion = params["protocolVersion"] as? String ?? "2025-06-18"
        return [
            "protocolVersion": requestedVersion,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "promptboard", "version": "1.1.0"],
        ]
    }

    private func handleToolCall(id: Any?, params: [String: Any]) {
        guard let toolName = params["name"] as? String else {
            send(errorResponse(id: id ?? NSNull(), code: -32602, message: "tools/call requires params.name"))
            return
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        switch PromptToolbox.call(name: toolName, arguments: arguments, repository: repository) {
        case .success(let payload):
            send(response(id: id, result: [
                "content": [["type": "text", "text": compactJSONString(payload)]],
                "structuredContent": payload,
                "isError": false,
            ]))
        case .domainError(let message):
            send(response(id: id, result: [
                "content": [["type": "text", "text": message]],
                "isError": true,
            ]))
        case .invalidParams(let message):
            send(errorResponse(id: id ?? NSNull(), code: -32602, message: message))
        }
    }

    private func response(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func compactJSONString(_ payload: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func send(_ payload: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }
        data.append(0x0A)
        standardOutput.write(data)
    }
}
