package com.remotecursor.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.remotecursor.app.ui.theme.ChatColors

private sealed class MdBlock {
    data class Paragraph(val text: String) : MdBlock()
    data class CodeBlock(val language: String, val code: String) : MdBlock()
    data class Heading(val level: Int, val text: String) : MdBlock()
    data class BulletItem(val text: String) : MdBlock()
    data class NumberedItem(val number: String, val text: String) : MdBlock()
}

private val downloadableExtensions = setOf(
    ".apk", ".ipa", ".zip", ".tar", ".gz", ".dmg", ".exe",
    ".pdf", ".png", ".jpg", ".jpeg", ".svg", ".mp4"
)

private val filePathRegex = Regex("""(?:/[\w.\-]+)+""")

private fun extractFilePaths(text: String): List<String> {
    return filePathRegex.findAll(text)
        .map { it.value }
        .filter { path -> downloadableExtensions.any { path.endsWith(it, ignoreCase = true) } }
        .toList()
}

@Composable
fun MarkdownText(
    content: String,
    modifier: Modifier = Modifier,
    onRunCommand: ((String) -> Unit)? = null,
    onDownloadFile: ((String) -> Unit)? = null
) {
    val blocks = remember(content) { parseMarkdown(content) }
    val clipboardManager = LocalClipboardManager.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        blocks.forEach { block ->
            when (block) {
                is MdBlock.Heading -> {
                    val style = when (block.level) {
                        1 -> MaterialTheme.typography.titleLarge
                        2 -> MaterialTheme.typography.titleMedium
                        else -> MaterialTheme.typography.titleSmall
                    }
                    Text(
                        text = block.text,
                        style = style,
                        fontWeight = FontWeight.Bold
                    )
                }

                is MdBlock.CodeBlock -> {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(containerColor = ChatColors.codeBg()),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Column {
                            if (block.language.isNotEmpty()) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 12.dp, vertical = 4.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        block.language,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    Row {
                                        IconButton(
                                            onClick = {
                                                clipboardManager.setText(AnnotatedString(block.code))
                                            },
                                            modifier = Modifier.size(28.dp)
                                        ) {
                                            Icon(
                                                Icons.Default.ContentCopy,
                                                contentDescription = "Copy",
                                                modifier = Modifier.size(16.dp)
                                            )
                                        }
                                        if (onRunCommand != null && block.language in setOf("bash", "sh", "shell", "zsh")) {
                                            IconButton(
                                                onClick = { onRunCommand(block.code) },
                                                modifier = Modifier.size(28.dp)
                                            ) {
                                                Icon(
                                                    Icons.Default.PlayArrow,
                                                    contentDescription = "Run on Mac",
                                                    modifier = Modifier.size(16.dp),
                                                    tint = MaterialTheme.colorScheme.primary
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                            Text(
                                text = block.code,
                                modifier = Modifier
                                    .horizontalScroll(rememberScrollState())
                                    .padding(12.dp),
                                fontFamily = FontFamily.Monospace,
                                fontSize = 13.sp,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                        }
                    }
                }

                is MdBlock.BulletItem -> {
                    Column {
                        Row(modifier = Modifier.padding(start = 8.dp)) {
                            Text("• ", fontWeight = FontWeight.Bold)
                            InlineMarkdown(block.text)
                        }
                        DownloadButtons(block.text, onDownloadFile)
                    }
                }

                is MdBlock.NumberedItem -> {
                    Column {
                        Row(modifier = Modifier.padding(start = 8.dp)) {
                            Text("${block.number}. ", fontWeight = FontWeight.Bold)
                            InlineMarkdown(block.text)
                        }
                        DownloadButtons(block.text, onDownloadFile)
                    }
                }

                is MdBlock.Paragraph -> {
                    Column {
                        InlineMarkdown(block.text)
                        DownloadButtons(block.text, onDownloadFile)
                    }
                }
            }
        }
    }
}

@Composable
private fun DownloadButtons(text: String, onDownloadFile: ((String) -> Unit)?) {
    if (onDownloadFile == null) return
    val paths = remember(text) { extractFilePaths(text) }
    paths.forEach { path ->
        TextButton(
            onClick = { onDownloadFile(path) },
            modifier = Modifier.padding(start = 8.dp),
            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp)
        ) {
            Icon(Icons.Default.Download, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(4.dp))
            Text("Download ${path.substringAfterLast("/")}", fontSize = 12.sp)
        }
    }
}

@Composable
private fun InlineMarkdown(text: String) {
    val annotated = remember(text) { parseInline(text) }
    Text(text = annotated)
}

private fun parseInline(text: String): AnnotatedString {
    return buildAnnotatedString {
        var i = 0
        val s = text
        while (i < s.length) {
            when {
                s.startsWith("**", i) || s.startsWith("__", i) -> {
                    val delim = s.substring(i, i + 2)
                    val end = s.indexOf(delim, i + 2)
                    if (end > 0) {
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                            append(s.substring(i + 2, end))
                        }
                        i = end + 2
                    } else {
                        append(s[i]); i++
                    }
                }
                s[i] == '*' || s[i] == '_' -> {
                    val delim = s[i]
                    val end = s.indexOf(delim, i + 1)
                    if (end > 0) {
                        withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                            append(s.substring(i + 1, end))
                        }
                        i = end + 1
                    } else {
                        append(s[i]); i++
                    }
                }
                s[i] == '`' -> {
                    val end = s.indexOf('`', i + 1)
                    if (end > 0) {
                        withStyle(SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 13.sp)) {
                            append(s.substring(i + 1, end))
                        }
                        i = end + 1
                    } else {
                        append(s[i]); i++
                    }
                }
                s[i] == '[' -> {
                    val closeBracket = s.indexOf(']', i)
                    val openParen = if (closeBracket > 0 && closeBracket + 1 < s.length) s.indexOf('(', closeBracket) else -1
                    val closeParen = if (openParen == closeBracket + 1) s.indexOf(')', openParen) else -1
                    if (closeParen > 0) {
                        val linkText = s.substring(i + 1, closeBracket)
                        withStyle(SpanStyle(textDecoration = TextDecoration.Underline)) {
                            append(linkText)
                        }
                        i = closeParen + 1
                    } else {
                        append(s[i]); i++
                    }
                }
                else -> {
                    append(s[i]); i++
                }
            }
        }
    }
}

private fun parseMarkdown(input: String): List<MdBlock> {
    val blocks = mutableListOf<MdBlock>()
    val lines = input.lines()
    var i = 0

    while (i < lines.size) {
        val line = lines[i]
        when {
            line.startsWith("```") -> {
                val lang = line.removePrefix("```").trim()
                val codeLines = mutableListOf<String>()
                i++
                while (i < lines.size && !lines[i].startsWith("```")) {
                    codeLines.add(lines[i])
                    i++
                }
                if (i < lines.size) i++ // skip closing ```
                blocks.add(MdBlock.CodeBlock(lang, codeLines.joinToString("\n")))
            }
            line.matches(Regex("^#{1,6}\\s+.*")) -> {
                val level = line.takeWhile { it == '#' }.length
                val text = line.drop(level).trim()
                blocks.add(MdBlock.Heading(level, text))
                i++
            }
            line.matches(Regex("^[-*+]\\s+.*")) -> {
                val text = line.replaceFirst(Regex("^[-*+]\\s+"), "")
                blocks.add(MdBlock.BulletItem(text))
                i++
            }
            line.matches(Regex("^\\d+\\.\\s+.*")) -> {
                val num = line.takeWhile { it.isDigit() }
                val text = line.replaceFirst(Regex("^\\d+\\.\\s+"), "")
                blocks.add(MdBlock.NumberedItem(num, text))
                i++
            }
            line.isBlank() -> {
                i++
            }
            else -> {
                val paraLines = mutableListOf(line)
                i++
                while (i < lines.size && lines[i].isNotBlank() && !lines[i].startsWith("```")
                    && !lines[i].matches(Regex("^#{1,6}\\s+.*"))
                    && !lines[i].matches(Regex("^[-*+]\\s+.*"))
                    && !lines[i].matches(Regex("^\\d+\\.\\s+.*"))
                ) {
                    paraLines.add(lines[i])
                    i++
                }
                blocks.add(MdBlock.Paragraph(paraLines.joinToString(" ")))
            }
        }
    }
    return blocks
}
