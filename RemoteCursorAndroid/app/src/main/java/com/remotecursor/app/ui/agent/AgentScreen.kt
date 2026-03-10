package com.remotecursor.app.ui.agent

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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.remotecursor.app.data.model.Conversation
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgentScreen(
    viewModel: AgentViewModel,
    onOpenChat: (Conversation) -> Unit
) {
    val selectedRepo by viewModel.selectedRepo.collectAsState()
    val conversations by viewModel.conversations.collectAsState()
    val repos by viewModel.repos.collectAsState()
    val favorites by viewModel.favoriteRepos.collectAsState()
    val error by viewModel.error.collectAsState()
    val isBrowsing by viewModel.isBrowsing.collectAsState()
    val browseItems by viewModel.browseItems.collectAsState()
    val browsePath by viewModel.browsePath.collectAsState()

    var showNewChatDialog by remember { mutableStateOf(false) }
    var newChatTitle by remember { mutableStateOf("") }
    var showDeleteRepoDialog by remember { mutableStateOf<String?>(null) }
    var showDeleteConvDialog by remember { mutableStateOf<Conversation?>(null) }

    LaunchedEffect(Unit) {
        viewModel.loadRepos()
    }

    if (isBrowsing) {
        FolderBrowser(
            items = browseItems,
            pathSegments = browsePath,
            onNavigate = { viewModel.browseTo(it) },
            onBack = { viewModel.browseBack() },
            onSelect = { viewModel.selectBrowsedFolder(it) },
            onCancel = { viewModel.stopBrowsing() }
        )
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(selectedRepo?.substringAfterLast("/") ?: "Agent")
                },
                navigationIcon = {
                    if (selectedRepo != null) {
                        IconButton(onClick = { viewModel.clearRepoSelection() }) {
                            Icon(Icons.Default.ArrowBack, "Back")
                        }
                    }
                },
                actions = {
                    if (selectedRepo != null) {
                        IconButton(onClick = {
                            showNewChatDialog = true
                            newChatTitle = ""
                        }) {
                            Icon(Icons.Default.Add, "New Chat")
                        }
                        IconButton(onClick = { viewModel.trustWorkspace(selectedRepo!!) }) {
                            Icon(Icons.Default.VerifiedUser, "Trust")
                        }
                    } else {
                        IconButton(onClick = { viewModel.startBrowsing() }) {
                            Icon(Icons.Default.FolderOpen, "Browse")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            error?.let { err ->
                Card(
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(8.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            err,
                            modifier = Modifier.weight(1f),
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            style = MaterialTheme.typography.bodySmall
                        )
                        IconButton(onClick = { viewModel.clearError() }) {
                            Icon(Icons.Default.Close, "Dismiss", modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }

            if (selectedRepo == null) {
                RepoListView(
                    repos = repos,
                    favorites = favorites,
                    onSelect = { viewModel.selectRepo(it) },
                    onRemoveFavorite = { viewModel.removeFavorite(it) },
                    onBrowse = { viewModel.startBrowsing() },
                    onDeleteConfirm = { showDeleteRepoDialog = it }
                )
            } else {
                ConversationListView(
                    conversations = conversations,
                    onOpen = onOpenChat,
                    onDelete = { showDeleteConvDialog = it }
                )
            }
        }
    }

    if (showNewChatDialog) {
        AlertDialog(
            onDismissRequest = { showNewChatDialog = false },
            title = { Text("New Chat") },
            text = {
                OutlinedTextField(
                    value = newChatTitle,
                    onValueChange = { newChatTitle = it },
                    label = { Text("Title (optional)") },
                    singleLine = true
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val title = newChatTitle.ifBlank { "Chat ${conversations.size + 1}" }
                    val convId = viewModel.createConversation(selectedRepo!!, title)
                    showNewChatDialog = false
                    onOpenChat(Conversation(id = convId, workspace = selectedRepo!!, title = title))
                }) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { showNewChatDialog = false }) { Text("Cancel") }
            }
        )
    }

    showDeleteConvDialog?.let { conv ->
        AlertDialog(
            onDismissRequest = { showDeleteConvDialog = null },
            title = { Text("Delete Chat") },
            text = { Text("Delete \"${conv.title}\"? This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteConversation(conv.id)
                    showDeleteConvDialog = null
                }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConvDialog = null }) { Text("Cancel") }
            }
        )
    }

    showDeleteRepoDialog?.let { repo ->
        AlertDialog(
            onDismissRequest = { showDeleteRepoDialog = null },
            title = { Text("Remove Repo") },
            text = { Text("Remove \"${repo.substringAfterLast("/")}\" and all its chats?") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteAllConversations(repo)
                    viewModel.removeFavorite(repo)
                    viewModel.deleteSession(repo)
                    showDeleteRepoDialog = null
                }) { Text("Remove", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteRepoDialog = null }) { Text("Cancel") }
            }
        )
    }
}

@Composable
private fun RepoListView(
    repos: List<String>,
    favorites: Set<String>,
    onSelect: (String) -> Unit,
    onRemoveFavorite: (String) -> Unit,
    onBrowse: () -> Unit,
    onDeleteConfirm: (String) -> Unit
) {
    val allRepos = remember(repos, favorites) {
        (favorites + repos).distinct()
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (favorites.isNotEmpty()) {
            item {
                Text(
                    "Favorites",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(bottom = 4.dp)
                )
            }
            items(favorites.toList()) { repo ->
                RepoCard(
                    repo = repo,
                    isFavorite = true,
                    onClick = { onSelect(repo) },
                    onLongClick = { onDeleteConfirm(repo) }
                )
            }
            item { Spacer(Modifier.height(8.dp)) }
        }

        val nonFavRepos = repos.filter { it !in favorites }
        if (nonFavRepos.isNotEmpty()) {
            item {
                Text(
                    "Available Repos",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 4.dp)
                )
            }
            items(nonFavRepos) { repo ->
                RepoCard(
                    repo = repo,
                    isFavorite = false,
                    onClick = { onSelect(repo) },
                    onLongClick = { }
                )
            }
        }

        item {
            Spacer(Modifier.height(16.dp))
            OutlinedButton(
                onClick = onBrowse,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.FolderOpen, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Browse for folder...")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RepoCard(
    repo: String,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                if (isFavorite) Icons.Default.Star else Icons.Default.Folder,
                contentDescription = null,
                tint = if (isFavorite) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(24.dp)
            )
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    repo.substringAfterLast("/"),
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    repo,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (isFavorite) {
                IconButton(onClick = onLongClick, modifier = Modifier.size(32.dp)) {
                    Icon(
                        Icons.Default.MoreVert,
                        contentDescription = "Options",
                        modifier = Modifier.size(18.dp)
                    )
                }
            }
            Icon(Icons.Default.ChevronRight, contentDescription = null)
        }
    }
}

@Composable
private fun ConversationListView(
    conversations: List<Conversation>,
    onOpen: (Conversation) -> Unit,
    onDelete: (Conversation) -> Unit
) {
    val dateFormat = remember { SimpleDateFormat("MMM d, h:mm a", Locale.getDefault()) }

    if (conversations.isEmpty()) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Default.ChatBubbleOutline,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    "No conversations yet",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    "Tap + to start a new chat",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    } else {
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(conversations, key = { it.id }) { conv ->
                Card(
                    onClick = { onOpen(conv) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    conv.title,
                                    fontWeight = if (conv.unreadCount > 0) FontWeight.Bold else FontWeight.Normal,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f, fill = false)
                                )
                                if (conv.unreadCount > 0) {
                                    Spacer(Modifier.width(8.dp))
                                    Badge {
                                        Text("${conv.unreadCount}")
                                    }
                                }
                            }
                            Text(
                                dateFormat.format(Date(conv.updatedAt)),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        IconButton(onClick = { onDelete(conv) }, modifier = Modifier.size(32.dp)) {
                            Icon(
                                Icons.Default.Delete,
                                contentDescription = "Delete",
                                modifier = Modifier.size(18.dp),
                                tint = MaterialTheme.colorScheme.error
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
private fun FolderBrowser(
    items: List<com.remotecursor.app.data.model.FileItem>,
    pathSegments: List<String>,
    onNavigate: (String) -> Unit,
    onBack: () -> Unit,
    onSelect: (String) -> Unit,
    onCancel: () -> Unit
) {
    val currentPath = "/" + pathSegments.joinToString("/")

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Select Folder") },
                navigationIcon = {
                    IconButton(onClick = onCancel) {
                        Icon(Icons.Default.Close, "Cancel")
                    }
                },
                actions = {
                    TextButton(onClick = { onSelect(currentPath) }) {
                        Text("Select This Folder")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (pathSegments.isNotEmpty()) {
                        IconButton(onClick = onBack, modifier = Modifier.size(24.dp)) {
                            Icon(Icons.Default.ArrowBack, "Back", modifier = Modifier.size(18.dp))
                        }
                        Spacer(Modifier.width(8.dp))
                    }
                    Text(
                        currentPath,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            LazyColumn(
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(items.filter { it.isDirectory }) { item ->
                    Card(
                        onClick = { onNavigate(item.path) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Default.Folder,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                            Spacer(Modifier.width(12.dp))
                            Text(
                                item.name,
                                modifier = Modifier.weight(1f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Icon(Icons.Default.ChevronRight, contentDescription = null)
                        }
                    }
                }
            }
        }
    }
}
