package cn.tenonai.apps.passby.core

import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The app draws QR codes with its own encoder. A separate decoder, used only here, reads them back. */
class QrTest {
    private fun decode(modules: Array<BooleanArray>): String {
        val scale = 8
        val quiet = 4
        val side = (Qr.SIZE + 2 * quiet) * scale
        val pixels = IntArray(side * side) { index ->
            val x = (index % side) / scale - quiet
            val y = (index / side) / scale - quiet
            val dark = x in 0 until Qr.SIZE && y in 0 until Qr.SIZE && modules[y][x]
            if (dark) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
        }
        val bitmap = BinaryBitmap(HybridBinarizer(RGBLuminanceSource(side, side, pixels)))
        return QRCodeReader().decode(bitmap, mapOf(DecodeHintType.PURE_BARCODE to true)).text
    }

    @Test
    fun theVectorExportCodeReadsBack() {
        val text = "7K3M9-Q2XHB-R8T4V-W6YZ0"
        val modules = Qr.encode(text)
        assertEquals(Qr.SIZE, modules.size)
        assertTrue(modules.all { it.size == Qr.SIZE })
        assertEquals(text, decode(modules))
    }

    @Test
    fun newExportCodesReadBack() {
        repeat(40) {
            val text = ExportSecret.grouped(ExportSecret.newCode())
            assertEquals(text, decode(Qr.encode(text)))
        }
    }

    @Test
    fun theLongestAndShortestInputsReadBack() {
        assertEquals("A", decode(Qr.encode("A")))
        val longest = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-:"
        assertEquals(38, longest.length)
        assertEquals(longest, decode(Qr.encode(longest)))
    }

    @Test(expected = IllegalArgumentException::class)
    fun lowerCaseIsRefused() {
        Qr.encode("abc")
    }
}
