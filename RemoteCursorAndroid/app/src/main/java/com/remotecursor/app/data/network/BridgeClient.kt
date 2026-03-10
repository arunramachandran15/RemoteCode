package com.remotecursor.app.data.network

import com.google.gson.Gson
import com.google.gson.JsonParser
import com.remotecursor.app.data.model.AgentResponse
import com.remotecursor.app.data.model.FileItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.URLEncoder
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class BridgeClient {
    private val gson = Gson()
    private var baseUrl = ""

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.MINUTES)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    val isConnected: Boolean get() = baseUrl.isNotEmpty()

    fun setBaseUrl(ip: String, port: Int) {
        baseUrl = "http://$ip:$port"
    }

    fun disconnect() {
        baseUrl = ""
    }

    suspend fun ping(): Boolean = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder().url("$baseUrl/status").build()
            val resp = client.newCall(req).await()
            resp.isSuccessful
        } catch (e: Exception) {
            false
        }
    }

    suspend fun listRepos(): List<String> = withContext(Dispatchers.IO) {
        val req = Request.Builder().url("$baseUrl/repos").build()
        val resp = client.newCall(req).await()
        val body = resp.body?.string() ?: "[]"
        val arr = JsonParser.parseString(body).asJsonArray
        arr.map { it.asString }
    }

    suspend fun browsePath(path: String): List<FileItem> = withContext(Dispatchers.IO) {
        val encoded = URLEncoder.encode(path, "UTF-8")
        val req = Request.Builder().url("$baseUrl/browse?path=$encoded").build()
        val resp = client.newCall(req).await()
        val body = resp.body?.string() ?: "[]"
        val arr = JsonParser.parseString(body).asJsonArray
        arr.map { el ->
            val obj = el.asJsonObject
            FileItem(
                name = obj.get("name")?.asString ?: "",
                path = obj.get("path")?.asString ?: "",
                isDirectory = obj.get("isDirectory")?.asBoolean ?: false,
                size = obj.get("size")?.asLong ?: 0
            )
        }
    }

    suspend fun listFiles(workspace: String, relativePath: String = ""): List<FileItem> = withContext(Dispatchers.IO) {
        val encodedWs = URLEncoder.encode(workspace, "UTF-8")
        val encodedPath = URLEncoder.encode(relativePath, "UTF-8")
        val req = Request.Builder()
            .url("$baseUrl/files?workspace=$encodedWs&path=$encodedPath")
            .build()
        val resp = client.newCall(req).await()
        val body = resp.body?.string() ?: "[]"
        val arr = JsonParser.parseString(body).asJsonArray
        arr.map { el ->
            val obj = el.asJsonObject
            FileItem(
                name = obj.get("name")?.asString ?: "",
                path = obj.get("path")?.asString ?: "",
                isDirectory = obj.get("isDirectory")?.asBoolean ?: false,
                size = obj.get("size")?.asLong ?: 0
            )
        }
    }

    suspend fun readFile(filePath: String): String = withContext(Dispatchers.IO) {
        val encoded = URLEncoder.encode(filePath, "UTF-8")
        val req = Request.Builder().url("$baseUrl/read-file?path=$encoded").build()
        val resp = client.newCall(req).await()
        resp.body?.string() ?: ""
    }

    suspend fun sendMessage(
        workspace: String,
        message: String,
        sessionId: String? = null,
        imagePath: String? = null,
        onChunk: (AgentResponse) -> Unit
    ): String? = withContext(Dispatchers.IO) {
        val jsonObj = com.google.gson.JsonObject().apply {
            addProperty("workspace", workspace)
            addProperty("message", message)
            sessionId?.let { addProperty("sessionId", it) }
            imagePath?.let { addProperty("imagePath", it) }
        }
        val body = jsonObj.toString().toRequestBody("application/json".toMediaType())
        val req = Request.Builder()
            .url("$baseUrl/agent")
            .post(body)
            .build()

        var resultSessionId: String? = sessionId
        val resp = client.newCall(req).await()
        val reader = BufferedReader(InputStreamReader(resp.body?.byteStream() ?: return@withContext null))

        var line: String?
        while (reader.readLine().also { line = it } != null) {
            val l = line ?: continue
            if (l.isBlank()) continue
            try {
                val parsed = gson.fromJson(l, AgentResponse::class.java)
                if (parsed.sessionId != null) resultSessionId = parsed.sessionId
                onChunk(parsed)
            } catch (_: Exception) {
                onChunk(AgentResponse(type = "text", content = l))
            }
        }
        resultSessionId
    }

    suspend fun runCommand(command: String): Pair<String, Int> = withContext(Dispatchers.IO) {
        val jsonObj = com.google.gson.JsonObject().apply {
            addProperty("command", command)
        }
        val body = jsonObj.toString().toRequestBody("application/json".toMediaType())
        val req = Request.Builder().url("$baseUrl/terminal").post(body).build()
        val resp = client.newCall(req).await()
        val respBody = resp.body?.string() ?: ""
        try {
            val obj = JsonParser.parseString(respBody).asJsonObject
            val output = obj.get("output")?.asString ?: obj.get("error")?.asString ?: respBody
            val exitCode = obj.get("exitCode")?.asInt ?: if (resp.isSuccessful) 0 else 1
            Pair(output, exitCode)
        } catch (_: Exception) {
            Pair(respBody, if (resp.isSuccessful) 0 else 1)
        }
    }

    suspend fun uploadImage(imageFile: File): String = withContext(Dispatchers.IO) {
        val body = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart(
                "image",
                imageFile.name,
                imageFile.asRequestBody("image/jpeg".toMediaType())
            )
            .build()
        val req = Request.Builder().url("$baseUrl/upload-image").post(body).build()
        val resp = client.newCall(req).await()
        val respBody = resp.body?.string() ?: ""
        val obj = JsonParser.parseString(respBody).asJsonObject
        obj.get("path")?.asString ?: throw Exception("Upload failed: $respBody")
    }

    suspend fun trustWorkspace(workspace: String): Boolean = withContext(Dispatchers.IO) {
        val jsonObj = com.google.gson.JsonObject().apply {
            addProperty("workspace", workspace)
        }
        val body = jsonObj.toString().toRequestBody("application/json".toMediaType())
        val req = Request.Builder().url("$baseUrl/trust-workspace").post(body).build()
        val resp = client.newCall(req).await()
        resp.isSuccessful
    }

    suspend fun deleteSession(workspace: String): Boolean = withContext(Dispatchers.IO) {
        val jsonObj = com.google.gson.JsonObject().apply {
            addProperty("workspace", workspace)
        }
        val body = jsonObj.toString().toRequestBody("application/json".toMediaType())
        val req = Request.Builder().url("$baseUrl/delete-session").post(body).build()
        val resp = client.newCall(req).await()
        resp.isSuccessful
    }

    suspend fun downloadFile(remotePath: String, destFile: File, onProgress: (Float) -> Unit = {}): File = withContext(Dispatchers.IO) {
        val encoded = URLEncoder.encode(remotePath, "UTF-8")
        val req = Request.Builder().url("$baseUrl/download?path=$encoded").build()
        val resp = client.newCall(req).await()
        if (!resp.isSuccessful) throw Exception("Download failed: ${resp.code}")

        val contentLength = resp.body?.contentLength() ?: -1
        val inputStream = resp.body?.byteStream() ?: throw Exception("Empty response")
        destFile.outputStream().use { output ->
            val buffer = ByteArray(8192)
            var bytesRead: Int
            var totalRead = 0L
            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                output.write(buffer, 0, bytesRead)
                totalRead += bytesRead
                if (contentLength > 0) {
                    onProgress((totalRead.toFloat() / contentLength).coerceAtMost(1f))
                }
            }
        }
        destFile
    }

    private suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
        cont.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: java.io.IOException) {
                if (cont.isActive) cont.resumeWithException(e)
            }
            override fun onResponse(call: Call, response: Response) {
                if (cont.isActive) cont.resume(response)
            }
        })
    }
}
