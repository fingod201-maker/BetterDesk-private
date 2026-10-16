package com.carriez.flutter_hbb

import android.content.Context
import android.util.Log
import java.io.IOException
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors

/**
 * IncomingConnectionManager — listens for operator connections on a local
 * TCP port and performs the permanent-password handshake before allowing
 * remote control.
 *
 * This runs inside the foreground service so it accepts connections even
 * when the Flutter UI is not visible.
 */
object IncomingConnectionManager {

    private const val TAG = "IncomingConnectionManager"
    private const val LISTEN_PORT = 21122 // same as CDAP port convention

    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null
    private var isRunning = false

    private val executor = Executors.newCachedThreadPool()

    /**
     * Start listening for incoming operator connections.
     */
    fun start(context: Context) {
        if (isRunning) return
        isRunning = true

        acceptThread = Thread {
            try {
                serverSocket = ServerSocket(LISTEN_PORT)
                serverSocket?.reuseAddress = true
                Log.i(TAG, "IncomingConnectionManager listening on port $LISTEN_PORT")

                while (isRunning) {
                    val client: Socket = serverSocket?.accept() ?: continue
                    executor.handle(client, context)
                }
            } catch (e: IOException) {
                if (isRunning) Log.e(TAG, "Incoming listener error", e)
            }
        }
        acceptThread?.isDaemon = true
        acceptThread?.start()
    }

    /**
     * Stop listening.
     */
    fun stop() {
        isRunning = false
        try { serverSocket?.close() } catch (_: IOException) {}
        serverSocket = null
        acceptThread = null
        executor.shutdown()
    }

    private object handle {
        fun run(client: Socket, context: Context) {
            Log.i(TAG, "Incoming connection from ${client.inetAddress.hostAddress}")
            try {
                // Perform permanent-password handshake
                val pwManager = UnattendedAccessManager
                // In a full implementation, we'd read the password from the
                // socket, verify via pwManager.verifyPassword(), then switch
                // to the remote-control protocol.
                client.close()
            } catch (e: IOException) {
                Log.e(TAG, "Incoming connection handler error", e)
            }
        }
    }
}
