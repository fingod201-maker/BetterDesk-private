package com.carriez.flutter_hbb

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        // Channel used to pass the baked-in server endpoint from the console Generator
        const val SERVER_HOST_CHANNEL = "betterdesk/server_host"
        const val USE_HTTPS_CHANNEL = "betterdesk/use_https"
    }
}
