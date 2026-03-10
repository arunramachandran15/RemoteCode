package com.remotecursor.app.service

import android.content.Context
import android.content.Intent
import android.os.Environment
import androidx.compose.runtime.mutableStateListOf
import androidx.core.content.FileProvider
import com.remotecursor.app.data.model.DownloadedFile
import com.remotecursor.app.data.network.BridgeClient
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File

data class ActiveDownload(
    val id: String = java.util.UUID.randomUUID().toString(),
    val remotePath: String,
    val fileName: String,
    var progress: Float = 0f,
    var error: String? = null,
    var isComplete: Boolean = false
)

class DownloadManager(private val context: Context) {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val _downloads = MutableStateFlow<List<DownloadedFile>>(emptyList())
    val downloads: StateFlow<List<DownloadedFile>> = _downloads

    private val _activeDownloads = MutableStateFlow<List<ActiveDownload>>(emptyList())
    val activeDownloads: StateFlow<List<ActiveDownload>> = _activeDownloads

    private val downloadsDir: File
        get() {
            val dir = File(context.getExternalFilesDir(null), "RemoteCursor")
            if (!dir.exists()) dir.mkdirs()
            return dir
        }

    init {
        reload()
    }

    fun reload() {
        val dir = downloadsDir
        if (!dir.exists()) {
            _downloads.value = emptyList()
            return
        }
        _downloads.value = dir.listFiles()
            ?.filter { it.isFile }
            ?.map { file ->
                DownloadedFile(
                    name = file.name,
                    localPath = file.absolutePath,
                    remotePath = "",
                    size = file.length(),
                    downloadedAt = file.lastModified()
                )
            }
            ?.sortedByDescending { it.downloadedAt }
            ?: emptyList()
    }

    fun startDownload(remotePath: String, bridgeClient: BridgeClient?) {
        if (bridgeClient == null) return

        val fileName = remotePath.substringAfterLast("/")
        val active = ActiveDownload(remotePath = remotePath, fileName = fileName)
        _activeDownloads.value = _activeDownloads.value + active

        scope.launch {
            try {
                val destFile = uniqueLocalFile(fileName)
                bridgeClient.downloadFile(remotePath, destFile) { progress ->
                    updateActiveDownload(active.id) { it.copy(progress = progress) }
                }
                updateActiveDownload(active.id) { it.copy(isComplete = true, progress = 1f) }
                reload()

                delay(2000)
                _activeDownloads.value = _activeDownloads.value.filter { it.id != active.id }
            } catch (e: Exception) {
                updateActiveDownload(active.id) { it.copy(error = e.message) }
            }
        }
    }

    fun deleteFile(file: DownloadedFile) {
        File(file.localPath).delete()
        reload()
    }

    fun deleteAll() {
        downloadsDir.listFiles()?.forEach { it.delete() }
        reload()
    }

    fun getShareIntent(file: DownloadedFile): Intent {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.provider", File(file.localPath))
        return Intent(Intent.ACTION_SEND).apply {
            type = "*/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    private fun uniqueLocalFile(fileName: String): File {
        var dest = File(downloadsDir, fileName)
        var counter = 1
        val name = fileName.substringBeforeLast(".")
        val ext = if (fileName.contains(".")) ".${fileName.substringAfterLast(".")}" else ""
        while (dest.exists()) {
            dest = File(downloadsDir, "${name}_$counter$ext")
            counter++
        }
        return dest
    }

    private fun updateActiveDownload(id: String, transform: (ActiveDownload) -> ActiveDownload) {
        _activeDownloads.value = _activeDownloads.value.map {
            if (it.id == id) transform(it) else it
        }
    }
}
