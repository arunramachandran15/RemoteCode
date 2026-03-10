package com.remotecursor.app

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.remotecursor.app.data.model.Conversation
import com.remotecursor.app.data.network.BridgeClient
import com.remotecursor.app.service.DownloadManager
import com.remotecursor.app.ui.agent.AgentScreen
import com.remotecursor.app.ui.agent.AgentViewModel
import com.remotecursor.app.ui.agent.ChatDetailScreen
import com.remotecursor.app.ui.connection.ConnectionScreen
import com.remotecursor.app.ui.downloads.DownloadsScreen
import com.remotecursor.app.ui.files.FileBrowserScreen
import com.remotecursor.app.ui.terminal.TerminalScreen
import com.remotecursor.app.ui.terminal.TerminalViewModel
import com.remotecursor.app.ui.theme.AppThemeMode
import com.remotecursor.app.ui.theme.RemoteCursorTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RemoteCursorMainApp()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RemoteCursorMainApp() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val prefs = remember { context.getSharedPreferences("remote_cursor", Context.MODE_PRIVATE) }

    var themeMode by remember {
        mutableStateOf(
            AppThemeMode.valueOf(prefs.getString("theme_mode", "SYSTEM") ?: "SYSTEM")
        )
    }

    val bridgeClient = remember { BridgeClient() }
    val downloadManager = remember { DownloadManager(context) }

    var isConnected by remember { mutableStateOf(false) }
    var isConnecting by remember { mutableStateOf(false) }
    var connectionError by remember { mutableStateOf<String?>(null) }

    val savedIp = remember { prefs.getString("last_ip", "") ?: "" }
    val savedPort = remember { prefs.getString("last_port", "3847") ?: "3847" }

    val agentViewModel: AgentViewModel = viewModel()
    val terminalViewModel: TerminalViewModel = viewModel()

    var currentTab by remember { mutableIntStateOf(0) }
    var activeChat by remember { mutableStateOf<Conversation?>(null) }

    val coroutineScope = rememberCoroutineScope()

    fun connectToBridge(ip: String, port: Int) {
        isConnecting = true
        connectionError = null
        coroutineScope.launch {
            bridgeClient.setBaseUrl(ip, port)
            val ok = bridgeClient.ping()
            if (ok) {
                prefs.edit()
                    .putString("last_ip", ip)
                    .putString("last_port", port.toString())
                    .apply()
                agentViewModel.bridgeClient = bridgeClient
                terminalViewModel.bridgeClient = bridgeClient
                isConnected = true
                agentViewModel.loadRepos()
            } else {
                connectionError = "Cannot reach bridge at $ip:$port. Check the IP and ensure the bridge is running."
                bridgeClient.disconnect()
            }
            isConnecting = false
        }
    }

    // Auto-connect on launch
    LaunchedEffect(Unit) {
        if (savedIp.isNotEmpty()) {
            val port = savedPort.toIntOrNull() ?: 3847
            connectToBridge(savedIp, port)
        }
    }

    // Auto-reconnect
    LaunchedEffect(isConnected) {
        if (isConnected) {
            while (true) {
                delay(15_000)
                if (!bridgeClient.ping()) {
                    isConnected = false
                    connectionError = "Connection lost. Reconnecting..."
                    var reconnected = false
                    repeat(5) {
                        delay(3_000)
                        if (bridgeClient.ping()) {
                            reconnected = true
                            return@repeat
                        }
                    }
                    if (reconnected) {
                        isConnected = true
                        connectionError = null
                    }
                }
            }
        }
    }

    fun cycleTheme() {
        themeMode = when (themeMode) {
            AppThemeMode.SYSTEM -> AppThemeMode.LIGHT
            AppThemeMode.LIGHT -> AppThemeMode.DARK
            AppThemeMode.DARK -> AppThemeMode.SYSTEM
        }
        prefs.edit().putString("theme_mode", themeMode.name).apply()
    }

    val themeLabel = when (themeMode) {
        AppThemeMode.SYSTEM -> "System"
        AppThemeMode.LIGHT -> "Light"
        AppThemeMode.DARK -> "Dark"
    }

    RemoteCursorTheme(themeMode = themeMode) {
        if (!isConnected) {
            ConnectionScreen(
                savedIp = savedIp,
                savedPort = savedPort,
                isConnecting = isConnecting,
                errorMessage = connectionError,
                onConnect = { ip, port -> connectToBridge(ip, port) },
                onThemeToggle = { cycleTheme() },
                themeLabel = themeLabel
            )
        } else if (activeChat != null) {
            ChatDetailScreen(
                conversation = activeChat!!,
                viewModel = agentViewModel,
                downloadManager = downloadManager,
                onBack = { activeChat = null },
                onRunCommand = { cmd ->
                    terminalViewModel.runCommand(cmd)
                    currentTab = 2
                    activeChat = null
                }
            )
        } else {
            Scaffold(
                bottomBar = {
                    NavigationBar {
                        NavigationBarItem(
                            selected = currentTab == 0,
                            onClick = { currentTab = 0 },
                            icon = { Icon(Icons.Default.SmartToy, null) },
                            label = { Text("Agent") }
                        )
                        NavigationBarItem(
                            selected = currentTab == 1,
                            onClick = { currentTab = 1 },
                            icon = { Icon(Icons.Default.Folder, null) },
                            label = { Text("Files") }
                        )
                        NavigationBarItem(
                            selected = currentTab == 2,
                            onClick = { currentTab = 2 },
                            icon = { Icon(Icons.Default.Terminal, null) },
                            label = { Text("Terminal") }
                        )
                        NavigationBarItem(
                            selected = currentTab == 3,
                            onClick = { currentTab = 3 },
                            icon = { Icon(Icons.Default.Download, null) },
                            label = { Text("Downloads") }
                        )
                    }
                }
            ) { padding ->
                Box(modifier = Modifier.padding(padding)) {
                    when (currentTab) {
                        0 -> AgentScreen(
                            viewModel = agentViewModel,
                            onOpenChat = { conv -> activeChat = conv }
                        )
                        1 -> FileBrowserScreen(
                            workspace = agentViewModel.selectedRepo.collectAsState().value,
                            bridgeClient = bridgeClient,
                            downloadManager = downloadManager
                        )
                        2 -> TerminalScreen(viewModel = terminalViewModel)
                        3 -> DownloadsScreen(
                            downloadManager = downloadManager,
                            bridgeClient = bridgeClient
                        )
                    }
                }
            }
        }
    }
}
