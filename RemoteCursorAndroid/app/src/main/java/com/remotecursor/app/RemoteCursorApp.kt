package com.remotecursor.app

import android.app.Application
import com.remotecursor.app.data.db.AppDatabase

class RemoteCursorApp : Application() {
    val database: AppDatabase by lazy { AppDatabase.getInstance(this) }
}
