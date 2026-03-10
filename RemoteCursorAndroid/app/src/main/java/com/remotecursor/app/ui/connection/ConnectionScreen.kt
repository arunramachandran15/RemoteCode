package com.remotecursor.app.ui.connection

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectionScreen(
    savedIp: String,
    savedPort: String,
    isConnecting: Boolean,
    errorMessage: String?,
    onConnect: (String, Int) -> Unit,
    onThemeToggle: () -> Unit,
    themeLabel: String
) {
    var octet1 by remember { mutableStateOf("") }
    var octet2 by remember { mutableStateOf("") }
    var octet3 by remember { mutableStateOf("") }
    var octet4 by remember { mutableStateOf("") }
    var port by remember { mutableStateOf("3847") }
    var fullUrl by remember { mutableStateOf("") }
    var isSyncing by remember { mutableStateOf(false) }

    val fr2 = remember { FocusRequester() }
    val fr3 = remember { FocusRequester() }
    val fr4 = remember { FocusRequester() }

    LaunchedEffect(savedIp, savedPort) {
        if (savedIp.isNotEmpty()) {
            val parts = savedIp.split(".")
            if (parts.size == 4) {
                octet1 = parts[0]; octet2 = parts[1]; octet3 = parts[2]; octet4 = parts[3]
            }
        } else {
            octet1 = "10"; octet2 = "0"; octet3 = "0"; octet4 = "247"
        }
        if (savedPort.isNotEmpty()) port = savedPort else port = "3847"
        fullUrl = "$octet1.$octet2.$octet3.$octet4:$port"
    }

    fun syncFromOctets() {
        if (isSyncing) return
        isSyncing = true
        fullUrl = "$octet1.$octet2.$octet3.$octet4:$port"
        isSyncing = false
    }

    fun syncFromUrl() {
        if (isSyncing) return
        isSyncing = true
        val parts = fullUrl.split(":")
        val ipStr = parts.getOrNull(0) ?: ""
        val portStr = parts.getOrNull(1) ?: ""
        val octets = ipStr.split(".")
        if (octets.size == 4) {
            octet1 = octets[0]; octet2 = octets[1]; octet3 = octets[2]; octet4 = octets[3]
        }
        if (portStr.isNotEmpty()) port = portStr
        isSyncing = false
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Remote Cursor") },
                actions = {
                    TextButton(onClick = onThemeToggle) {
                        Text(themeLabel)
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(
                Icons.Default.DesktopWindows,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.primary
            )

            Spacer(Modifier.height(16.dp))

            Text(
                "Connect to Mac Bridge",
                style = MaterialTheme.typography.headlineSmall
            )

            Spacer(Modifier.height(8.dp))

            Text(
                "Enter the IP address of the Mac running the Remote Cursor bridge",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Spacer(Modifier.height(32.dp))

            Text("IP Address", style = MaterialTheme.typography.labelMedium)
            Spacer(Modifier.height(8.dp))

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center
            ) {
                @Composable
                fun OctetField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier, focusReq: FocusRequester? = null, nextFocus: FocusRequester? = null) {
                    OutlinedTextField(
                        value = value,
                        onValueChange = { v ->
                            val filtered = v.filter { it.isDigit() }.take(3)
                            onValueChange(filtered)
                            syncFromOctets()
                            if (filtered.length == 3 && nextFocus != null) {
                                nextFocus.requestFocus()
                            }
                        },
                        modifier = modifier
                            .width(64.dp)
                            .then(if (focusReq != null) Modifier.focusRequester(focusReq) else Modifier),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyLarge.copy(textAlign = TextAlign.Center)
                    )
                }

                OctetField(octet1, { octet1 = it }, nextFocus = fr2)
                Text(".", Modifier.padding(horizontal = 2.dp), style = MaterialTheme.typography.headlineMedium)
                OctetField(octet2, { octet2 = it }, focusReq = fr2, nextFocus = fr3)
                Text(".", Modifier.padding(horizontal = 2.dp), style = MaterialTheme.typography.headlineMedium)
                OctetField(octet3, { octet3 = it }, focusReq = fr3, nextFocus = fr4)
                Text(".", Modifier.padding(horizontal = 2.dp), style = MaterialTheme.typography.headlineMedium)
                OctetField(octet4, { octet4 = it }, focusReq = fr4)
            }

            Spacer(Modifier.height(12.dp))

            Text("Port", style = MaterialTheme.typography.labelMedium)
            Spacer(Modifier.height(4.dp))

            OutlinedTextField(
                value = port,
                onValueChange = {
                    port = it.filter { c -> c.isDigit() }.take(5)
                    syncFromOctets()
                },
                modifier = Modifier.width(120.dp),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(textAlign = TextAlign.Center)
            )

            Spacer(Modifier.height(16.dp))

            OutlinedTextField(
                value = fullUrl,
                onValueChange = {
                    fullUrl = it
                    syncFromUrl()
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Full address") },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyMedium.copy(textAlign = TextAlign.Center)
            )

            Spacer(Modifier.height(24.dp))

            if (errorMessage != null) {
                Card(
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        errorMessage,
                        modifier = Modifier.padding(12.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Spacer(Modifier.height(16.dp))
            }

            Button(
                onClick = {
                    val ip = "$octet1.$octet2.$octet3.$octet4"
                    val p = port.toIntOrNull() ?: 3847
                    onConnect(ip, p)
                },
                enabled = !isConnecting && octet1.isNotEmpty() && octet4.isNotEmpty(),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(12.dp)
            ) {
                if (isConnecting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp
                    )
                    Spacer(Modifier.width(8.dp))
                    Text("Connecting...")
                } else {
                    Icon(Icons.Default.Link, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Connect")
                }
            }
        }
    }
}
