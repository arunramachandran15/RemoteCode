package com.remotecursor.app.ui.agent

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import com.remotecursor.app.data.model.ChatMessage
import com.remotecursor.app.data.model.Conversation
import com.remotecursor.app.service.DownloadManager
import com.remotecursor.app.ui.components.MarkdownText
import com.remotecursor.app.ui.theme.ChatColors
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatDetailScreen(
    conversation: Conversation,
    viewModel: AgentViewModel,
    downloadManager: DownloadManager,
    onBack: () -> Unit,
    onRunCommand: ((String) -> Unit)? = null
) {
    val messages by viewModel.messages.collectAsState()
    val streamingText by viewModel.streamingText.collectAsState()
    val isStreaming by viewModel.isStreaming.collectAsState()
    val error by viewModel.error.collectAsState()

    var inputText by remember { mutableStateOf("") }
    var pendingImageUri by remember { mutableStateOf<Uri?>(null) }
    var pendingImageRemotePath by remember { mutableStateOf<String?>(null) }
    var showVoicePreview by remember { mutableStateOf(false) }
    var voiceTranscript by remember { mutableStateOf("") }
    var showImageOptions by remember { mutableStateOf(false) }
    var commandResult by remember { mutableStateOf<Pair<String, String>?>(null) }

    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    val context = LocalContext.current
    val dateFormat = remember { SimpleDateFormat("h:mm a", Locale.getDefault()) }

    var isUserScrolling by remember { mutableStateOf(false) }

    LaunchedEffect(conversation.id) {
        viewModel.loadMessages(conversation.id)
    }

    LaunchedEffect(messages.size, streamingText) {
        if (!isUserScrolling && messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size + if (streamingText.isNotEmpty()) 1 else 0)
        }
    }

    // Camera photo URI
    var cameraPhotoUri by remember { mutableStateOf<Uri?>(null) }

    val cameraLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.TakePicture()
    ) { success ->
        if (success && cameraPhotoUri != null) {
            pendingImageUri = cameraPhotoUri
        }
    }

    val galleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri ->
        if (uri != null) {
            pendingImageUri = uri
        }
    }

    val speechLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val matches = result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
        val transcript = matches?.firstOrNull() ?: ""
        if (transcript.isNotEmpty()) {
            voiceTranscript = transcript
            showVoicePreview = true
        }
    }

    val cameraPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            val photoFile = createTempImageFile(context)
            cameraPhotoUri = FileProvider.getUriForFile(context, "${context.packageName}.provider", photoFile)
            cameraLauncher.launch(cameraPhotoUri!!)
        }
    }

    val micPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak your message...")
            }
            speechLauncher.launch(intent)
        }
    }

    fun sendCurrentMessage() {
        val text = inputText.trim()
        if (text.isEmpty() && pendingImageRemotePath == null) return
        viewModel.sendMessage(
            conversationId = conversation.id,
            workspace = conversation.workspace,
            text = text,
            imagePath = pendingImageRemotePath
        )
        inputText = ""
        pendingImageUri = null
        pendingImageRemotePath = null
        isUserScrolling = false
    }

    fun uploadAndSend() {
        val uri = pendingImageUri ?: return
        coroutineScope.launch {
            try {
                val file = uriToFile(context, uri)
                val remotePath = viewModel.bridgeClient?.uploadImage(file)
                if (remotePath != null && remotePath.isNotEmpty()) {
                    pendingImageRemotePath = remotePath
                    sendCurrentMessage()
                }
            } catch (e: Exception) {
                viewModel._error.value = "Image upload failed: ${e.message}"
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            conversation.title,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            conversation.workspace.substringAfterLast("/"),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, "Back")
                    }
                }
            )
        },
        bottomBar = {
            Column {
                // Image preview
                pendingImageUri?.let { uri ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                        colors = CardDefaults.cardColors(containerColor = ChatColors.inputBarBg())
                    ) {
                        Row(
                            modifier = Modifier.padding(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            AsyncImage(
                                model = uri,
                                contentDescription = "Preview",
                                modifier = Modifier
                                    .size(60.dp)
                                    .clip(RoundedCornerShape(8.dp)),
                                contentScale = ContentScale.Crop
                            )
                            Spacer(Modifier.width(8.dp))
                            Text("Image attached", modifier = Modifier.weight(1f))
                            IconButton(onClick = {
                                pendingImageUri = null
                                pendingImageRemotePath = null
                            }) {
                                Icon(Icons.Default.Close, "Remove")
                            }
                        }
                    }
                }

                // Voice preview
                if (showVoicePreview) {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                        colors = CardDefaults.cardColors(containerColor = ChatColors.inputBarBg())
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Text("Voice Transcript:", style = MaterialTheme.typography.labelSmall)
                            Spacer(Modifier.height(4.dp))
                            Text(voiceTranscript, style = MaterialTheme.typography.bodyMedium)
                            Spacer(Modifier.height(8.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                OutlinedButton(onClick = {
                                    inputText = voiceTranscript
                                    showVoicePreview = false
                                    voiceTranscript = ""
                                }) { Text("Use Text") }
                                OutlinedButton(onClick = {
                                    showVoicePreview = false
                                    micPermLauncher.launch(Manifest.permission.RECORD_AUDIO)
                                }) { Text("Re-record") }
                                OutlinedButton(onClick = {
                                    showVoicePreview = false
                                    voiceTranscript = ""
                                }) { Text("Cancel") }
                            }
                        }
                    }
                }

                // Input bar
                Surface(
                    tonalElevation = 2.dp,
                    color = ChatColors.inputBarBg()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(8.dp),
                        verticalAlignment = Alignment.Bottom
                    ) {
                        IconButton(onClick = { showImageOptions = true }) {
                            Icon(Icons.Default.AttachFile, "Attach")
                        }
                        IconButton(onClick = {
                            micPermLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }) {
                            Icon(Icons.Default.Mic, "Voice")
                        }

                        OutlinedTextField(
                            value = inputText,
                            onValueChange = { inputText = it },
                            modifier = Modifier
                                .weight(1f)
                                .heightIn(min = 40.dp, max = 120.dp),
                            placeholder = { Text("Ask agent...") },
                            maxLines = 4,
                            trailingIcon = {
                                if (inputText.isNotEmpty()) {
                                    IconButton(onClick = { inputText = "" }) {
                                        Icon(Icons.Default.Clear, "Clear")
                                    }
                                }
                            },
                            shape = RoundedCornerShape(20.dp)
                        )

                        Spacer(Modifier.width(4.dp))

                        FilledIconButton(
                            onClick = {
                                if (pendingImageUri != null && pendingImageRemotePath == null) {
                                    uploadAndSend()
                                } else {
                                    sendCurrentMessage()
                                }
                            },
                            enabled = !isStreaming && (inputText.isNotBlank() || pendingImageUri != null)
                        ) {
                            Icon(Icons.Default.Send, "Send")
                        }
                    }
                }
            }
        }
    ) { padding ->
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(messages, key = { it.id }) { msg ->
                MessageBubble(
                    message = msg,
                    dateFormat = dateFormat,
                    onRunCommand = onRunCommand,
                    onDownloadFile = { path ->
                        downloadManager.startDownload(path, viewModel.bridgeClient)
                    }
                )
            }

            if (streamingText.isNotEmpty()) {
                item("streaming") {
                    StreamingBubble(streamingText)
                }
            }

            if (isStreaming && streamingText.isEmpty()) {
                item("loading") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(8.dp),
                        horizontalArrangement = Arrangement.Start
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp
                        )
                        Spacer(Modifier.width(8.dp))
                        Text("Agent is thinking...", fontStyle = FontStyle.Italic)
                    }
                }
            }
        }
    }

    if (showImageOptions) {
        AlertDialog(
            onDismissRequest = { showImageOptions = false },
            title = { Text("Add Image") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = {
                            showImageOptions = false
                            cameraPermLauncher.launch(Manifest.permission.CAMERA)
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.CameraAlt, null)
                        Spacer(Modifier.width(8.dp))
                        Text("Take Photo")
                    }
                    OutlinedButton(
                        onClick = {
                            showImageOptions = false
                            galleryLauncher.launch("image/*")
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.PhotoLibrary, null)
                        Spacer(Modifier.width(8.dp))
                        Text("Choose from Gallery")
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showImageOptions = false }) { Text("Cancel") }
            }
        )
    }

    commandResult?.let { (cmd, result) ->
        AlertDialog(
            onDismissRequest = { commandResult = null },
            title = { Text("Command Result") },
            text = {
                Column {
                    Text("$ $cmd", style = MaterialTheme.typography.labelSmall)
                    Spacer(Modifier.height(4.dp))
                    Text(result, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, fontSize = 12.sp)
                }
            },
            confirmButton = {
                TextButton(onClick = { commandResult = null }) { Text("OK") }
            }
        )
    }
}

@Composable
private fun MessageBubble(
    message: ChatMessage,
    dateFormat: SimpleDateFormat,
    onRunCommand: ((String) -> Unit)?,
    onDownloadFile: ((String) -> Unit)?
) {
    val isUser = message.role == "user"

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = if (isUser) Alignment.End else Alignment.Start
    ) {
        Card(
            shape = RoundedCornerShape(
                topStart = 16.dp,
                topEnd = 16.dp,
                bottomStart = if (isUser) 16.dp else 4.dp,
                bottomEnd = if (isUser) 4.dp else 16.dp
            ),
            colors = CardDefaults.cardColors(
                containerColor = if (isUser) ChatColors.userBubble() else ChatColors.assistantBubble()
            ),
            modifier = Modifier.widthIn(max = 320.dp)
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                if (isUser) {
                    Text(message.content)
                } else {
                    MarkdownText(
                        content = message.content,
                        onRunCommand = onRunCommand,
                        onDownloadFile = onDownloadFile
                    )
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    dateFormat.format(Date(message.timestamp)),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun StreamingBubble(text: String) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.Start
    ) {
        Card(
            shape = RoundedCornerShape(16.dp, 16.dp, 16.dp, 4.dp),
            colors = CardDefaults.cardColors(containerColor = ChatColors.assistantBubble()),
            modifier = Modifier.widthIn(max = 320.dp)
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                Text(text)
                Spacer(Modifier.height(4.dp))
                LinearProgressIndicator(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(2.dp)
                )
            }
        }
    }
}

private fun createTempImageFile(context: Context): File {
    val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
    val storageDir = context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)
    return File.createTempFile("IMG_${timestamp}_", ".jpg", storageDir)
}

private fun uriToFile(context: Context, uri: Uri): File {
    val inputStream = context.contentResolver.openInputStream(uri) ?: throw Exception("Cannot read image")
    val file = File(context.cacheDir, "upload_${System.currentTimeMillis()}.jpg")
    file.outputStream().use { out -> inputStream.copyTo(out) }
    return file
}
