package com.remotecursor.app.ui.terminal

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.remotecursor.app.data.model.TerminalEntry
import com.remotecursor.app.ui.theme.ChatColors
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerminalScreen(viewModel: TerminalViewModel) {
    val history by viewModel.history.collectAsState()
    val isRunning by viewModel.isRunning.collectAsState()
    val currentOutput by viewModel.currentOutput.collectAsState()

    var command by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    val clipboardManager = LocalClipboardManager.current
    val dateFormat = remember { SimpleDateFormat("h:mm a", Locale.getDefault()) }

    val suggestions = listOf("ls", "pwd", "git status", "git log --oneline -5", "df -h", "uptime")

    LaunchedEffect(history.size) {
        if (history.isNotEmpty()) {
            listState.animateScrollToItem(0)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Terminal") },
                actions = {
                    IconButton(onClick = { viewModel.clearHistory() }) {
                        Icon(Icons.Default.DeleteSweep, "Clear History")
                    }
                }
            )
        },
        bottomBar = {
            Column {
                // Suggestion chips
                Row(
                    modifier = Modifier
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    suggestions.forEach { suggestion ->
                        SuggestionChip(
                            onClick = { command = suggestion },
                            label = { Text(suggestion, fontSize = 12.sp) }
                        )
                    }
                }

                Surface(tonalElevation = 2.dp, color = ChatColors.inputBarBg()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "$ ",
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.primary
                        )
                        OutlinedTextField(
                            value = command,
                            onValueChange = { command = it },
                            modifier = Modifier.weight(1f),
                            placeholder = { Text("Enter command...") },
                            singleLine = true,
                            shape = RoundedCornerShape(20.dp),
                            textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace)
                        )
                        Spacer(Modifier.width(4.dp))
                        FilledIconButton(
                            onClick = {
                                viewModel.runCommand(command)
                                command = ""
                            },
                            enabled = !isRunning && command.isNotBlank()
                        ) {
                            if (isRunning) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(20.dp),
                                    strokeWidth = 2.dp
                                )
                            } else {
                                Icon(Icons.Default.PlayArrow, "Run")
                            }
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
            contentPadding = PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            reverseLayout = true
        ) {
            if (currentOutput.isNotEmpty() && isRunning) {
                item("current") {
                    TerminalOutputCard(
                        command = "Running...",
                        output = currentOutput,
                        timestamp = null,
                        exitCode = null,
                        clipboardManager = clipboardManager
                    )
                }
            }

            items(history, key = { it.id }) { entry ->
                TerminalOutputCard(
                    command = entry.command,
                    output = entry.output,
                    timestamp = dateFormat.format(Date(entry.timestamp)),
                    exitCode = entry.exitCode,
                    clipboardManager = clipboardManager
                )
            }
        }
    }
}

@Composable
private fun TerminalOutputCard(
    command: String,
    output: String,
    timestamp: String?,
    exitCode: Int?,
    clipboardManager: androidx.compose.ui.platform.ClipboardManager
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = ChatColors.codeBg()
        ),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "$ $command",
                    fontFamily = FontFamily.Monospace,
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f)
                )
                if (exitCode != null) {
                    Spacer(Modifier.width(8.dp))
                    Badge(
                        containerColor = if (exitCode == 0) MaterialTheme.colorScheme.secondary
                        else MaterialTheme.colorScheme.error
                    ) {
                        Text(if (exitCode == 0) "OK" else "ERR")
                    }
                }
                IconButton(
                    onClick = { clipboardManager.setText(AnnotatedString(output)) },
                    modifier = Modifier.size(28.dp)
                ) {
                    Icon(Icons.Default.ContentCopy, "Copy", modifier = Modifier.size(16.dp))
                }
            }

            if (output.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text(
                    output,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }

            if (timestamp != null) {
                Spacer(Modifier.height(4.dp))
                Text(
                    timestamp,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
