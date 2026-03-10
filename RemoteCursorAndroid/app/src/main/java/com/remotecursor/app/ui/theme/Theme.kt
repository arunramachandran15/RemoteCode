package com.remotecursor.app.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF7AA2F7),
    onPrimary = Color(0xFF1A1B26),
    primaryContainer = Color(0xFF3D59A1),
    secondary = Color(0xFF9ECE6A),
    tertiary = Color(0xFFBB9AF7),
    background = Color(0xFF1A1B26),
    surface = Color(0xFF1A1B26),
    surfaceVariant = Color(0xFF24283B),
    onBackground = Color(0xFFA9B1D6),
    onSurface = Color(0xFFA9B1D6),
    onSurfaceVariant = Color(0xFF565F89),
    error = Color(0xFFF7768E),
    outline = Color(0xFF3B4261)
)

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF2E59D9),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD6E2FF),
    secondary = Color(0xFF4E8C3A),
    tertiary = Color(0xFF7C5CBF),
    background = Color(0xFFF8F9FC),
    surface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFFF0F1F5),
    onBackground = Color(0xFF1A1B26),
    onSurface = Color(0xFF1A1B26),
    onSurfaceVariant = Color(0xFF6B7280),
    error = Color(0xFFD32F2F),
    outline = Color(0xFFDADCE0)
)

enum class AppThemeMode { SYSTEM, LIGHT, DARK }

object ChatColors {
    @Composable
    fun userBubble(): Color = if (isSystemInDarkTheme()) Color(0xFF2A3A5C) else Color(0xFFE3ECFF)

    @Composable
    fun assistantBubble(): Color = if (isSystemInDarkTheme()) Color(0xFF24283B) else Color(0xFFF5F5F8)

    @Composable
    fun codeBg(): Color = if (isSystemInDarkTheme()) Color(0xFF1E2030) else Color(0xFFEEEFF3)

    @Composable
    fun inputBarBg(): Color = if (isSystemInDarkTheme()) Color(0xFF1F2335) else Color(0xFFFFFFFF)
}

@Composable
fun RemoteCursorTheme(
    themeMode: AppThemeMode = AppThemeMode.SYSTEM,
    content: @Composable () -> Unit
) {
    val darkTheme = when (themeMode) {
        AppThemeMode.SYSTEM -> isSystemInDarkTheme()
        AppThemeMode.LIGHT -> false
        AppThemeMode.DARK -> true
    }

    val colorScheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && themeMode == AppThemeMode.SYSTEM -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography(),
        content = content
    )
}
