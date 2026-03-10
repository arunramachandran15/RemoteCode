package com.remotecursor.app.ui.agent

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.remotecursor.app.RemoteCursorApp
import com.remotecursor.app.data.model.ChatMessage
import com.remotecursor.app.data.model.Conversation
import com.remotecursor.app.data.network.BridgeClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

class AgentViewModel(application: Application) : AndroidViewModel(application) {
    private val db = (application as RemoteCursorApp).database
    private val prefs = application.getSharedPreferences("remote_cursor", Context.MODE_PRIVATE)
    private val gson = Gson()

    var bridgeClient: BridgeClient? = null

    private val _repos = MutableStateFlow<List<String>>(emptyList())
    val repos: StateFlow<List<String>> = _repos

    private val _favoriteRepos = MutableStateFlow<Set<String>>(emptySet())
    val favoriteRepos: StateFlow<Set<String>> = _favoriteRepos

    private val _selectedRepo = MutableStateFlow<String?>(null)
    val selectedRepo: StateFlow<String?> = _selectedRepo

    private val _conversations = MutableStateFlow<List<Conversation>>(emptyList())
    val conversations: StateFlow<List<Conversation>> = _conversations

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages

    private val _streamingText = MutableStateFlow("")
    val streamingText: StateFlow<String> = _streamingText

    private val _isStreaming = MutableStateFlow(false)
    val isStreaming: StateFlow<Boolean> = _isStreaming

    val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private val _browsePath = MutableStateFlow<List<String>>(emptyList())
    val browsePath: StateFlow<List<String>> = _browsePath

    private val _browseItems = MutableStateFlow<List<com.remotecursor.app.data.model.FileItem>>(emptyList())
    val browseItems: StateFlow<List<com.remotecursor.app.data.model.FileItem>> = _browseItems

    private val _isBrowsing = MutableStateFlow(false)
    val isBrowsing: StateFlow<Boolean> = _isBrowsing

    private val sessionIds: MutableMap<String, String> = mutableMapOf()

    init {
        loadFavorites()
        loadSessionIds()
    }

    fun loadRepos() {
        viewModelScope.launch {
            try {
                val list = bridgeClient?.listRepos() ?: emptyList()
                _repos.value = list
            } catch (e: Exception) {
                _error.value = "Failed to load repos: ${e.message}"
            }
        }
    }

    fun selectRepo(repo: String) {
        _selectedRepo.value = repo
        addFavorite(repo)
        loadConversations(repo)
    }

    fun clearRepoSelection() {
        _selectedRepo.value = null
        _conversations.value = emptyList()
    }

    fun loadConversations(workspace: String) {
        viewModelScope.launch {
            db.conversationDao().getByWorkspace(workspace).collect { list ->
                _conversations.value = list
            }
        }
    }

    fun createConversation(workspace: String, title: String): String {
        val id = UUID.randomUUID().toString()
        val conv = Conversation(
            id = id,
            workspace = workspace,
            title = title,
            createdAt = System.currentTimeMillis(),
            updatedAt = System.currentTimeMillis()
        )
        viewModelScope.launch {
            db.conversationDao().upsert(conv)
        }
        return id
    }

    fun deleteConversation(conversationId: String) {
        viewModelScope.launch {
            db.messageDao().deleteByConversation(conversationId)
            db.conversationDao().delete(conversationId)
        }
    }

    fun deleteAllConversations(workspace: String) {
        viewModelScope.launch {
            val convs = _conversations.value
            convs.forEach { db.messageDao().deleteByConversation(it.id) }
            db.conversationDao().deleteByWorkspace(workspace)
        }
    }

    fun loadMessages(conversationId: String, limit: Int = 100, offset: Int = 0) {
        viewModelScope.launch {
            val msgs = db.messageDao().getMessages(conversationId, limit, offset)
            _messages.value = msgs
            db.conversationDao().markRead(conversationId)
        }
    }

    fun sendMessage(
        conversationId: String,
        workspace: String,
        text: String,
        imagePath: String? = null
    ) {
        val userMsg = ChatMessage(
            id = UUID.randomUUID().toString(),
            conversationId = conversationId,
            role = "user",
            content = if (imagePath != null) "$text\n[Image: $imagePath]" else text,
            timestamp = System.currentTimeMillis()
        )

        viewModelScope.launch {
            db.messageDao().insert(userMsg)
            _messages.value = _messages.value + userMsg
            db.conversationDao().upsert(
                (_conversations.value.find { it.id == conversationId }
                    ?: Conversation(id = conversationId, workspace = workspace, title = text.take(50)))
                    .copy(updatedAt = System.currentTimeMillis())
            )

            _isStreaming.value = true
            _streamingText.value = ""
            _error.value = null

            try {
                val sessionId = sessionIds[workspace]
                val newSessionId = bridgeClient?.sendMessage(
                    workspace = workspace,
                    message = text,
                    sessionId = sessionId,
                    imagePath = imagePath
                ) { chunk ->
                    val content = chunk.content ?: chunk.text ?: ""
                    if (content.isNotEmpty()) {
                        _streamingText.value += content
                    }
                    if (chunk.sessionId != null) {
                        sessionIds[workspace] = chunk.sessionId
                        saveSessionIds()
                    }
                }

                if (newSessionId != null) {
                    sessionIds[workspace] = newSessionId
                    saveSessionIds()
                }

                val fullResponse = _streamingText.value.ifEmpty { "(No response)" }
                val assistantMsg = ChatMessage(
                    id = UUID.randomUUID().toString(),
                    conversationId = conversationId,
                    role = "assistant",
                    content = fullResponse,
                    timestamp = System.currentTimeMillis()
                )
                db.messageDao().insert(assistantMsg)
                _messages.value = _messages.value + assistantMsg
                db.conversationDao().upsert(
                    (_conversations.value.find { it.id == conversationId }
                        ?: Conversation(id = conversationId, workspace = workspace, title = text.take(50)))
                        .copy(updatedAt = System.currentTimeMillis(), unreadCount = 0)
                )
            } catch (e: Exception) {
                val errMsg = if (e.message?.contains("trust", ignoreCase = true) == true) {
                    "Workspace trust required. Trust from Mac or use Trust button."
                } else {
                    "Error: ${e.message}"
                }
                _error.value = errMsg
            } finally {
                _isStreaming.value = false
                _streamingText.value = ""
            }
        }
    }

    fun trustWorkspace(workspace: String) {
        viewModelScope.launch {
            try {
                val ok = bridgeClient?.trustWorkspace(workspace) ?: false
                if (!ok) _error.value = "Trust failed. Open in Cursor on Mac and trust manually."
            } catch (e: Exception) {
                _error.value = "Trust error: ${e.message}"
            }
        }
    }

    fun deleteSession(workspace: String) {
        viewModelScope.launch {
            try {
                bridgeClient?.deleteSession(workspace)
                sessionIds.remove(workspace)
                saveSessionIds()
            } catch (_: Exception) {}
        }
    }

    fun removeFavorite(repo: String) {
        val updated = _favoriteRepos.value - repo
        _favoriteRepos.value = updated
        prefs.edit().putStringSet("favorite_repos", updated).apply()
    }

    private fun addFavorite(repo: String) {
        val updated = _favoriteRepos.value + repo
        _favoriteRepos.value = updated
        prefs.edit().putStringSet("favorite_repos", updated).apply()
    }

    private fun loadFavorites() {
        _favoriteRepos.value = prefs.getStringSet("favorite_repos", emptySet()) ?: emptySet()
    }

    private fun saveSessionIds() {
        prefs.edit().putString("session_ids", gson.toJson(sessionIds)).apply()
    }

    private fun loadSessionIds() {
        val json = prefs.getString("session_ids", null) ?: return
        try {
            val type = object : TypeToken<Map<String, String>>() {}.type
            val map: Map<String, String> = gson.fromJson(json, type)
            sessionIds.clear()
            sessionIds.putAll(map)
        } catch (_: Exception) {}
    }

    // Folder browsing for repo selection
    fun startBrowsing() {
        _isBrowsing.value = true
        _browsePath.value = emptyList()
        browseTo("/")
    }

    fun stopBrowsing() {
        _isBrowsing.value = false
        _browseItems.value = emptyList()
        _browsePath.value = emptyList()
    }

    fun browseTo(path: String) {
        viewModelScope.launch {
            try {
                val items = bridgeClient?.browsePath(path) ?: emptyList()
                _browseItems.value = items
                val segments = path.split("/").filter { it.isNotEmpty() }
                _browsePath.value = segments
            } catch (e: Exception) {
                _error.value = "Browse error: ${e.message}"
            }
        }
    }

    fun browseBack() {
        val segments = _browsePath.value
        if (segments.isEmpty()) {
            stopBrowsing()
            return
        }
        val parentPath = "/" + segments.dropLast(1).joinToString("/")
        browseTo(parentPath)
    }

    fun selectBrowsedFolder(path: String) {
        stopBrowsing()
        selectRepo(path)
    }

    fun clearError() {
        _error.value = null
    }
}
