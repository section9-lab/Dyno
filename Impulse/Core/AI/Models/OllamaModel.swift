import Foundation
import SwiftCodingAgent

struct OllamaModel: AgentModel {
    let baseURL: URL
    let modelName: String
    let timeout: TimeInterval

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        modelName: String = "gpt-oss:20b",
        timeout: TimeInterval = 120
    ) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.timeout = timeout
    }

    nonisolated func generate(request: ModelRequest) async throws -> ModelResponse {
        let url = baseURL.appendingPathComponent("api/chat")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = timeout

        let body = try makeRequestBody(from: request)
        urlRequest.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "OllamaModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OllamaModel", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Ollama error (\(http.statusCode)): \(text)"])
        }

        return try parseResponse(data)
    }

    nonisolated private func makeRequestBody(from request: ModelRequest) throws -> Data {
        let messages = request.messages.map { messageToDictionary($0) }
        let tools = request.tools.map { toolToDictionary($0) }

        let payload: [String: Any] = [
            "model": modelName,
            "stream": false,
            "messages": messages,
            "tools": tools
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    nonisolated private func messageToDictionary(_ message: AgentMessage) -> [String: Any] {
        var dict: [String: Any] = [
            "role": roleToOllamaRole(message.role),
            "content": message.content
        ]

        if let toolName = message.toolName {
            dict["name"] = toolName
        }
        if let toolCallID = message.toolCallID {
            dict["tool_call_id"] = toolCallID
        }

        return dict
    }

    nonisolated private func toolToDictionary(_ tool: ModelToolSpec) -> [String: Any] {
        let schemaData = tool.argumentSchemaJSON.data(using: .utf8) ?? Data("{}".utf8)
        let schemaObject = (try? JSONSerialization.jsonObject(with: schemaData, options: [])) ?? ["type": "object"]

        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": schemaObject
            ]
        ]
    }

    nonisolated private func roleToOllamaRole(_ role: AgentRole) -> String {
        switch role {
        case .system: return "system"
        case .user: return "user"
        case .assistant: return "assistant"
        case .tool: return "tool"
        }
    }

    nonisolated private func parseResponse(_ data: Data) throws -> ModelResponse {
        guard
            let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            let message = root["message"] as? [String: Any]
        else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OllamaModel", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama JSON: \(text)"])
        }

        let content = (message["content"] as? String) ?? ""

        let rawToolCalls = (message["tool_calls"] as? [[String: Any]]) ?? []
        let toolCalls: [ToolCall] = rawToolCalls.compactMap { call in
            guard let function = call["function"] as? [String: Any],
                  let name = function["name"] as? String
            else { return nil }

            let id = (call["id"] as? String) ?? UUID().uuidString
            let argumentsJSON: String

            if let argString = function["arguments"] as? String {
                argumentsJSON = argString
            } else if let argObject = function["arguments"] {
                let data = (try? JSONSerialization.data(withJSONObject: argObject, options: [])) ?? Data("{}".utf8)
                argumentsJSON = String(data: data, encoding: .utf8) ?? "{}"
            } else {
                argumentsJSON = "{}"
            }

            return ToolCall(id: id, name: name, argumentsJSON: argumentsJSON)
        }

        return ModelResponse(content: content, toolCalls: toolCalls)
    }
}
