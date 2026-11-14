package cn.tenonai.apps.passby.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/**
 * The app's icons, drawn here as line art on a 24-unit grid. The app does not carry an icon
 * library. The colour comes from the Icon that shows them.
 */
object Icons {
    private fun icon(block: ImageVector.Builder.() -> Unit): ImageVector =
        ImageVector.Builder(defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f).apply(block).build()

    private fun ImageVector.Builder.line(block: PathBuilder.() -> Unit) {
        path(
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 1.8f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
            pathBuilder = block,
        )
    }

    private fun ImageVector.Builder.solid(block: PathBuilder.() -> Unit) {
        path(fill = SolidColor(Color.Black), pathBuilder = block)
    }

    private fun PathBuilder.circle(cx: Float, cy: Float, r: Float) {
        moveTo(cx - r, cy)
        arcToRelative(r, r, 0f, true, true, 2 * r, 0f)
        arcToRelative(r, r, 0f, true, true, -2 * r, 0f)
        close()
    }

    private fun PathBuilder.roundRect(x: Float, y: Float, w: Float, h: Float, r: Float) {
        moveTo(x + r, y)
        horizontalLineToRelative(w - 2 * r)
        arcToRelative(r, r, 0f, false, true, r, r)
        verticalLineToRelative(h - 2 * r)
        arcToRelative(r, r, 0f, false, true, -r, r)
        horizontalLineToRelative(-(w - 2 * r))
        arcToRelative(r, r, 0f, false, true, -r, -r)
        verticalLineToRelative(-(h - 2 * r))
        arcToRelative(r, r, 0f, false, true, r, -r)
        close()
    }

    val Search: ImageVector by lazy {
        icon {
            line {
                circle(10.5f, 10.5f, 6f)
                moveTo(15f, 15f)
                lineTo(20f, 20f)
            }
        }
    }

    val Close: ImageVector by lazy {
        icon {
            line {
                moveTo(6f, 6f)
                lineTo(18f, 18f)
                moveTo(18f, 6f)
                lineTo(6f, 18f)
            }
        }
    }

    val Plus: ImageVector by lazy {
        icon {
            line {
                moveTo(12f, 5f)
                lineTo(12f, 19f)
                moveTo(5f, 12f)
                lineTo(19f, 12f)
            }
        }
    }

    val Back: ImageVector by lazy {
        icon {
            line {
                moveTo(19f, 12f)
                lineTo(5f, 12f)
                moveTo(11f, 6f)
                lineTo(5f, 12f)
                lineTo(11f, 18f)
            }
        }
    }

    val Chevron: ImageVector by lazy {
        icon {
            line {
                moveTo(9f, 6f)
                lineTo(15f, 12f)
                lineTo(9f, 18f)
            }
        }
    }

    val More: ImageVector by lazy {
        icon {
            solid {
                circle(12f, 5f, 1.6f)
                circle(12f, 12f, 1.6f)
                circle(12f, 19f, 1.6f)
            }
        }
    }

    val Check: ImageVector by lazy {
        icon {
            line {
                moveTo(5f, 12.5f)
                lineTo(10f, 17.5f)
                lineTo(19f, 7f)
            }
        }
    }

    /** Two sheets, one behind the other. */
    val Copy: ImageVector by lazy {
        icon {
            line {
                roundRect(8.5f, 8.5f, 11.5f, 11.5f, 2f)
                moveTo(5f, 15f)
                verticalLineTo(7f)
                arcToRelative(2f, 2f, 0f, false, true, 2f, -2f)
                horizontalLineTo(15f)
            }
        }
    }

    private fun PathBuilder.eyeOutline() {
        moveTo(2.5f, 12f)
        curveTo(5f, 7f, 8.5f, 5f, 12f, 5f)
        curveTo(15.5f, 5f, 19f, 7f, 21.5f, 12f)
        curveTo(19f, 17f, 15.5f, 19f, 12f, 19f)
        curveTo(8.5f, 19f, 5f, 17f, 2.5f, 12f)
        close()
    }

    val Eye: ImageVector by lazy {
        icon {
            line {
                eyeOutline()
                circle(12f, 12f, 3f)
            }
        }
    }

    val EyeOff: ImageVector by lazy {
        icon {
            line {
                eyeOutline()
                circle(12f, 12f, 3f)
                moveTo(4f, 4f)
                lineTo(20f, 20f)
            }
        }
    }

    val Folder: ImageVector by lazy {
        icon {
            line {
                moveTo(3.5f, 6.5f)
                arcToRelative(1.5f, 1.5f, 0f, false, true, 1.5f, -1.5f)
                horizontalLineToRelative(4.2f)
                lineToRelative(2f, 2f)
                horizontalLineToRelative(7.8f)
                arcToRelative(1.5f, 1.5f, 0f, false, true, 1.5f, 1.5f)
                verticalLineToRelative(9f)
                arcToRelative(1.5f, 1.5f, 0f, false, true, -1.5f, 1.5f)
                horizontalLineToRelative(-14f)
                arcToRelative(1.5f, 1.5f, 0f, false, true, -1.5f, -1.5f)
                close()
            }
        }
    }

    val Trash: ImageVector by lazy {
        icon {
            line {
                moveTo(4f, 7f)
                lineTo(20f, 7f)
                moveTo(9f, 7f)
                verticalLineTo(5f)
                horizontalLineTo(15f)
                verticalLineTo(7f)
                moveTo(6.5f, 7f)
                lineTo(7.5f, 19.5f)
                horizontalLineTo(16.5f)
                lineTo(17.5f, 7f)
                moveTo(10f, 10.5f)
                verticalLineTo(16.5f)
                moveTo(14f, 10.5f)
                verticalLineTo(16.5f)
            }
        }
    }

    /** A die showing five, for the password generator. */
    val Dice: ImageVector by lazy {
        icon {
            line { roundRect(4f, 4f, 16f, 16f, 3f) }
            solid {
                circle(8.5f, 8.5f, 1.2f)
                circle(15.5f, 8.5f, 1.2f)
                circle(12f, 12f, 1.2f)
                circle(8.5f, 15.5f, 1.2f)
                circle(15.5f, 15.5f, 1.2f)
            }
        }
    }

    /** Three sliders, for settings. */
    val Sliders: ImageVector by lazy {
        icon {
            line {
                moveTo(4f, 6f)
                lineTo(7f, 6f)
                circle(9f, 6f, 2f)
                moveTo(11f, 6f)
                lineTo(20f, 6f)

                moveTo(4f, 12f)
                lineTo(13f, 12f)
                circle(15f, 12f, 2f)
                moveTo(17f, 12f)
                lineTo(20f, 12f)

                moveTo(4f, 18f)
                lineTo(6f, 18f)
                circle(8f, 18f, 2f)
                moveTo(10f, 18f)
                lineTo(20f, 18f)
            }
        }
    }

    /** An arrow turning back, for restoring a deleted password. */
    val Restore: ImageVector by lazy {
        icon {
            line {
                moveTo(4f, 9f)
                horizontalLineTo(13f)
                arcToRelative(5.5f, 5.5f, 0f, false, true, 0f, 11f)
                horizontalLineTo(8f)
                moveTo(8f, 5f)
                lineTo(4f, 9f)
                lineTo(8f, 13f)
            }
        }
    }

    val Lock: ImageVector by lazy {
        icon {
            line {
                roundRect(5.5f, 10.5f, 13f, 9.5f, 2f)
                moveTo(8.5f, 10.5f)
                verticalLineTo(8f)
                arcToRelative(3.5f, 3.5f, 0f, false, true, 7f, 0f)
                verticalLineTo(10.5f)
            }
        }
    }
}
