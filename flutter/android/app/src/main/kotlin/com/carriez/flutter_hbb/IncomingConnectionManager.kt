package com.carriez.flutter_hbb

import android.content.Context
import android.util.Log
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.Executors

object IncomingConnectionManager {

    private const val TAG = "IncomingConnectionManager"
    private const val LISTEN_PORT = 21122

    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null
    private var isRunning = false

    private val executor = Executors.newCachedThreadPool()

    fun start(context: Context) {
        if (isRunning) return
        isRunning = true

        acceptThread = Thread {
            try {
                serverSocket = ServerSocket(LISTEN_PORT)
                serverSocket?.reuseAddress = true
                Log.i(TAG, "IncomingConnectionManager listening on port $LISTEN_PORT")

                while (isRunning) {
                    try {
                        val client: Socket = serverSocket?.accept() ?: continue
                        executor.handle(client, context)
                    } catch (e: IOException) {
                        if (isRunning) Log.w(TAG, "Accept error", e)
                    }
                }
            } catch (e: IOException) {
                if (isRunning) Log.e(TAG, "Incoming listener error", e)
            }
        }
        acceptThread?.isDaemon = true
        acceptThread?.start()
    }

    fun stop() {
        isRunning = false
        try { serverSocket?.close() } catch (_: IOException) {}
        serverSocket = null
        acceptThread = null
        executor.shutdown()
    }

    private object handle {
        fun run(client: Socket, context: Context) {
            val remoteAddress = client.inetAddress.hostAddress
            Log.i(TAG, "Incoming connection from $remoteAddress")

            var input: InputStream? = null
            var output: OutputStream? = null

            try {
                input = client.inputStream
                output = client.outputStream

                val password = readString(input!!)
                Log.d(TAG, "Received password attempt from $remoteAddress")

                val verified = UnattendedAccessManager.verifyPassword(password, context)

                val result = if (verified) "OK" else "AUTH_FAILED"
                writeString(output!!, result)
                output!!.flush()

                if (!verified) {
                    Log.w(TAG, "Authentication failed from $remoteAddress")
                    return
                }

                Log.i(TAG, "Authenticated operator from $remoteAddress")

                while (isRunning && !client.isClosed) {
                    try {
                        val cmd = readString(input!!)
                        when (cmd) {
                            "PING" -> {
                                writeString(output!!, "PONG")
                                output!!.flush()
                            }
                            "FRAME_REQUEST" -> {
                                writeString(output!!, "FRAME_READY")
                                output!!.flush()
                            }
                            "DISCONNECT" -> {
                                Log.i(TAG, "Operator disconnected from $remoteAddress")
                                return
                            }
                            else -> {
                                Log.w(TAG, "Unknown command: $cmd")
                            }
                        }
                    } catch (e: IOException) {
                        Log.d(TAG, "Connection handler ending: $e")
                        break
                    }
                }
            } catch (e: IOException) {
                Log.e(TAG, "Connection handler error from $remoteAddress", e)
            } finally {
                try { input?.close() } catch (_: IOException) {}
                try { output?.close() } catch (_: IOException) {}
                try { client.close() } catch (_: IOException) {}
            }
        }
    }

    private fun readString(input: InputStream): String {
        val lenBuf = ByteArray(4)
        var totalRead = 0
        while (totalRead < 4) {
            val read = input.read(lenBuf, totalRead, 4 - totalRead)
            if (read < 0) throw IOException("Stream closed")
            totalRead += read
        }
        val len = ByteBuffer.wrap(lenBuf).getInt()
        val buf = ByteArray(len)
        totalRead = 0
        while (totalRead < len) {
            val read = input.read(buf, totalRead, len - totalRead)
            if (read < 0) throw IOException("Stream closed")
            totalRead += read
        }
        return String(buf, charset = java.nio.charset.StandardCharsets.UTF_8)
    }

    private fun writeString(output: OutputStream, s: String) {
        val bytes = s.toByteArray(Charsets.UTF_8)
        val lenBuf = ByteArray(4)
        ByteBuffer.wrap(lenBuf).putInt(bytes.size)
        output.write(lenBuf)
        output.write(bytes)
    }
}
