//
// Item.swift
// Impulse
//
// Created by jackwang on 2026/3/27.
//
//  Created by jackwang on 2026/3/27.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    var content: String = ""
    var isUser: Bool = true
    var kind: String = "assistant_message"
    var conversationID: String = ""
    var projectPath: String = ""

    init(
        timestamp: Date,
        content: String = "",
        isUser: Bool = true,
        kind: String? = nil,
        conversationID: String? = nil,
        projectPath: String? = nil
    ) {
        self.timestamp = timestamp
        self.content = content
        self.isUser = isUser
        self.kind = kind ?? (isUser ? "user_message" : "assistant_message")
        self.conversationID = conversationID ?? ""
        self.projectPath = projectPath ?? ""
    }
}
