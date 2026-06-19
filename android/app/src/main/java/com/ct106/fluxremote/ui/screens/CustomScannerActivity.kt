package com.ct106.flux_remote.ui.screens

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import com.ct106.flux_remote.R
import com.journeyapps.barcodescanner.CaptureActivity

/**
 * Custom CaptureActivity to force portrait orientation and provide scanning guidance.
 */
class CustomScannerActivity : CaptureActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        addContentView(
            ScannerGuideView(this),
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        addContentView(
            TextView(this).apply {
                text = "×"
                contentDescription = getString(R.string.back)
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 32f)
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(0x73000000)
                }
                setOnClickListener { finish() }
            },
            FrameLayout.LayoutParams(dp(48), dp(48), Gravity.TOP or Gravity.START).apply {
                topMargin = dp(24)
                marginStart = dp(20)
            }
        )
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()
}

private class ScannerGuideView(activity: CustomScannerActivity) : View(activity) {
    private val density = resources.displayMetrics.density
    private val frameSize = 250f * density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 3f * density
        setShadowLayer(4f * density, 0f, 0f, 0x99000000.toInt())
    }

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, paint)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val size = minOf(frameSize, width * 0.75f, height * 0.6f)
        val left = (width - size) / 2f
        val top = (height - size) / 2f
        canvas.drawRoundRect(left, top, left + size, top + size, 18f * density, 18f * density, paint)
    }
}
