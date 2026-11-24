package com.example.gospel_frontend

import android.content.Context
import android.print.PrintAttributes
import android.print.PrintManager
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Keep the view alive while Chromium lays out the full table for printing.
    private var preparingPrint: WebView? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gospel_topics/print")
            .setMethodCallHandler { call, result ->
                if (call.method != "printTable") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val title = call.argument<String>("title")
                val html = call.argument<String>("html")
                if (html == null || title == null || preparingPrint != null) {
                    result.error("print_unavailable", "A print job could not be started.", null)
                    return@setMethodCallHandler
                }

                val webView = WebView(this)
                preparingPrint = webView
                pendingResult = result
                webView.setWebViewClient(object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String) {
                        if (preparingPrint !== view) return
                        preparingPrint = null
                        pendingResult = null
                        try {
                            val manager = getSystemService(Context.PRINT_SERVICE) as PrintManager
                            val attributes = PrintAttributes.Builder()
                                .setMediaSize(PrintAttributes.MediaSize.ISO_A4.asLandscape())
                                .build()
                            manager.print(title, view.createPrintDocumentAdapter(title), attributes)
                            result.success(null)
                        } catch (error: RuntimeException) {
                            view.destroy()
                            result.error("print_unavailable", error.localizedMessage, null)
                        }
                    }
                })
                webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
            }
    }

    override fun onDestroy() {
        pendingResult?.error("print_cancelled", "The print window was closed.", null)
        pendingResult = null
        preparingPrint?.destroy()
        preparingPrint = null
        super.onDestroy()
    }
}
