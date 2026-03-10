package com.remotecursor.app.ui.terminal

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.remotecursor.app.RemoteCursorApp
import com.remotecursor.app.data.model.TerminalEntry
import com.remotecursor.app.data.network.BridgeClient
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

class TerminalViewModel(application: Application) : AndroidViewModel(application) {
    private val db = (application as RemoteCursorApp).database

    var bridgeClient: BridgeClient? = null

    val history: StateFlow<List<TerminalEntry>> = db.terminalDao().recent(100)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning

    private val _currentOutput = MutableStateFlow("")
    val currentOutput: StateFlow<String> = _currentOutput

    fun runCommand(command: String) {
        if (command.isBlank()) return
        viewModelScope.launch {
            _isRunning.value = true
            _currentOutput.value = ""
            try {
                val (output, exitCode) = bridgeClient?.runCommand(command) ?: Pair("Not connected", 1)
                _currentOutput.value = output
                db.terminalDao().insert(
                    TerminalEntry(
                        command = command,
                        output = output,
                        exitCode = exitCode
                    )
                )
            } catch (e: Exception) {
                val errOutput = "Error: ${e.message}"
                _currentOutput.value = errOutput
                db.terminalDao().insert(
                    TerminalEntry(
                        command = command,
                        output = errOutput,
                        exitCode = 1
                    )
                )
            } finally {
                _isRunning.value = false
            }
        }
    }

    fun clearHistory() {
        viewModelScope.launch {
            db.terminalDao().clearAll()
        }
    }
}
