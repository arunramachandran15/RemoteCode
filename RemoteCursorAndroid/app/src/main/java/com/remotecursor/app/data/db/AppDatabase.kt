package com.remotecursor.app.data.db

import android.content.Context
import androidx.room.*
import com.remotecursor.app.data.model.ChatMessage
import com.remotecursor.app.data.model.Conversation
import com.remotecursor.app.data.model.TerminalEntry
import kotlinx.coroutines.flow.Flow

@Dao
interface ConversationDao {
    @Query("SELECT * FROM conversations WHERE workspace = :workspace ORDER BY updatedAt DESC")
    fun getByWorkspace(workspace: String): Flow<List<Conversation>>

    @Query("SELECT DISTINCT workspace FROM conversations ORDER BY updatedAt DESC")
    fun distinctWorkspaces(): Flow<List<String>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(conversation: Conversation)

    @Query("DELETE FROM conversations WHERE id = :id")
    suspend fun delete(id: String)

    @Query("DELETE FROM conversations WHERE workspace = :workspace")
    suspend fun deleteByWorkspace(workspace: String)

    @Query("UPDATE conversations SET unreadCount = 0 WHERE id = :id")
    suspend fun markRead(id: String)
}

@Dao
interface MessageDao {
    @Query("SELECT * FROM messages WHERE conversationId = :conversationId ORDER BY timestamp ASC LIMIT :limit OFFSET :offset")
    suspend fun getMessages(conversationId: String, limit: Int = 100, offset: Int = 0): List<ChatMessage>

    @Query("SELECT COUNT(*) FROM messages WHERE conversationId = :conversationId")
    suspend fun messageCount(conversationId: String): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(message: ChatMessage)

    @Query("DELETE FROM messages WHERE conversationId = :conversationId")
    suspend fun deleteByConversation(conversationId: String)

    @Query("SELECT * FROM messages WHERE conversationId = :conversationId ORDER BY timestamp DESC LIMIT 1")
    suspend fun lastMessage(conversationId: String): ChatMessage?
}

@Dao
interface TerminalDao {
    @Query("SELECT * FROM terminal_history ORDER BY timestamp DESC LIMIT :limit")
    fun recent(limit: Int = 50): Flow<List<TerminalEntry>>

    @Insert
    suspend fun insert(entry: TerminalEntry)

    @Query("DELETE FROM terminal_history")
    suspend fun clearAll()
}

@Database(
    entities = [Conversation::class, ChatMessage::class, TerminalEntry::class],
    version = 1,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun conversationDao(): ConversationDao
    abstract fun messageDao(): MessageDao
    abstract fun terminalDao(): TerminalDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "remote_cursor.db"
                ).build().also { INSTANCE = it }
            }
        }
    }
}
