package com.remotecursor.app.data.model

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "conversations")
data class Conversation(
    @PrimaryKey val id: String,
    val workspace: String,
    val title: String,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val unreadCount: Int = 0
)

@Entity(tableName = "messages")
data class ChatMessage(
    @PrimaryKey val id: String,
    val conversationId: String,
    val role: String, // "user" or "assistant"
    val content: String,
    val timestamp: Long = System.currentTimeMillis(),
    val isRead: Boolean = true
)

@Entity(tableName = "terminal_history")
data class TerminalEntry(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val command: String,
    val output: String,
    val timestamp: Long = System.currentTimeMillis(),
    val exitCode: Int? = null
)

data class FileItem(
    val name: String,
    val path: String,
    val isDirectory: Boolean,
    val size: Long = 0
) {
    val iconName: String
        get() = when {
            isDirectory -> "folder"
            name.endsWith(".kt") || name.endsWith(".java") -> "code"
            name.endsWith(".swift") -> "code"
            name.endsWith(".js") || name.endsWith(".ts") -> "code"
            name.endsWith(".json") -> "data_object"
            name.endsWith(".xml") -> "code"
            name.endsWith(".md") -> "description"
            name.endsWith(".png") || name.endsWith(".jpg") || name.endsWith(".jpeg") -> "image"
            name.endsWith(".apk") || name.endsWith(".ipa") -> "android"
            else -> "insert_drive_file"
        }
}

data class AgentResponse(
    val type: String? = null,
    val content: String? = null,
    val text: String? = null,
    val title: String? = null,
    val sessionId: String? = null,
    val error: String? = null
)

data class BridgeStatus(
    val connected: Boolean,
    val version: String = ""
)

data class DownloadedFile(
    val name: String,
    val localPath: String,
    val remotePath: String,
    val size: Long,
    val downloadedAt: Long
) {
    val formattedSize: String
        get() {
            val kb = size / 1024.0
            return if (kb > 1024) String.format("%.1f MB", kb / 1024.0)
            else String.format("%.1f KB", kb)
        }
}
