package com.remotecursor.app.ui.files

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.remotecursor.app.data.model.FileItem
import com.remotecursor.app.data.network.BridgeClient
import com.remotecursor.app.service.DownloadManager
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FileBrowserScreen(
    workspace: String?,
    bridgeClient: BridgeClient?,
    downloadManager: DownloadManager
) {
    var currentPath by remember { mutableStateOf("") }
    var pathStack by remember { mutableStateOf(listOf<String>()) }
    var files by remember { mutableStateOf<List<FileItem>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var selectedFile by remember { mutableStateOf<FileItem?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    val coroutineScope = rememberCoroutineScope()
    val clipboardManager = LocalClipboardManager.current

    fun loadFiles(relativePath: String = currentPath) {
        if (workspace == null || bridgeClient == null) return
        coroutineScope.launch {
            isLoading = true
            error = null
            try {
                files = bridgeClient.listFiles(workspace, relativePath)
                currentPath = relativePath
            } catch (e: Exception) {
                error = e.message
            } finally {
                isLoading = false
            }
        }
    }

    LaunchedEffect(workspace) {
        if (workspace != null) loadFiles("")
    }

    if (selectedFile != null) {
        CodeViewerScreen(
            file = selectedFile!!,
            bridgeClient = bridgeClient,
            downloadManager = downloadManager,
            onBack = { selectedFile = null }
        )
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Files")
                        if (workspace != null) {
                            Text(
                                if (currentPath.isEmpty()) workspace.substringAfterLast("/")
                                else currentPath,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                },
                navigationIcon = {
                    if (pathStack.isNotEmpty()) {
                        IconButton(onClick = {
                            val prev = pathStack.lastOrNull() ?: ""
                            pathStack = pathStack.dropLast(1)
                            loadFiles(prev)
                        }) {
                            Icon(Icons.Default.ArrowBack, "Back")
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { loadFiles(currentPath) }) {
                        Icon(Icons.Default.Refresh, "Refresh")
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            when {
                workspace == null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("Select a repo in the Agent tab first")
                    }
                }

                isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }

                error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(Icons.Default.Error, null, tint = MaterialTheme.colorScheme.error)
                            Text(error ?: "", color = MaterialTheme.colorScheme.error)
                            Spacer(Modifier.height(8.dp))
                            Button(onClick = { loadFiles(currentPath) }) { Text("Retry") }
                        }
                    }
                }

                else -> {
                    LazyColumn(
                        contentPadding = PaddingValues(8.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        items(files.sortedWith(compareByDescending<FileItem> { it.isDirectory }.thenBy { it.name })) { file ->
                            FileRow(
                                file = file,
                                onClick = {
                                    if (file.isDirectory) {
                                        pathStack = pathStack + currentPath
                                        loadFiles(file.path.removePrefix(workspace).removePrefix("/"))
                                    } else {
                                        selectedFile = file
                                    }
                                },
                                onDownload = {
                                    downloadManager.startDownload(file.path, bridgeClient)
                                },
                                onCopyPath = {
                                    clipboardManager.setText(AnnotatedString(file.path))
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FileRow(
    file: FileItem,
    onClick: () -> Unit,
    onDownload: () -> Unit,
    onCopyPath: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = if (file.isDirectory) Icons.Default.Folder else Icons.Default.InsertDriveFile,
                contentDescription = null,
                tint = if (file.isDirectory) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(24.dp)
            )
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    file.name,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (!file.isDirectory && file.size > 0) {
                    Text(
                        formatFileSize(file.size),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            if (!file.isDirectory) {
                IconButton(onClick = onDownload, modifier = Modifier.size(32.dp)) {
                    Icon(
                        Icons.Default.Download,
                        contentDescription = "Download",
                        modifier = Modifier.size(18.dp)
                    )
                }
                IconButton(onClick = onCopyPath, modifier = Modifier.size(32.dp)) {
                    Icon(
                        Icons.Default.ContentCopy,
                        contentDescription = "Copy path",
                        modifier = Modifier.size(18.dp)
                    )
                }
            } else {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            }
        }
    }
}

private fun formatFileSize(size: Long): String {
    val kb = size / 1024.0
    return if (kb > 1024) String.format("%.1f MB", kb / 1024.0)
    else String.format("%.1f KB", kb)
}
