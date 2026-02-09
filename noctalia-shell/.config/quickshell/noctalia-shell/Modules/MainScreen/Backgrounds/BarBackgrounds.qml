import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Services.UI
import qs.Widgets

/**
* BarBackgrounds - Unified Shape container for bar background only.
*
* Matches the old opacity behavior:
* - If separate bar opacity is enabled, use bar background opacity.
* - Otherwise, use panel background opacity (unified behavior).
*/
Item {
  id: root

  // Reference Bar
  required property var bar

  // Reference to window root (for screen access)
  required property var windowRoot

  readonly property color panelBackgroundColor: Color.mSurface

  anchors.fill: parent

  Item {
    anchors.fill: parent

    layer.enabled: true
    opacity: Settings.data.bar.useSeparateOpacity ? Settings.data.bar.backgroundOpacity : Settings.data.ui.panelBackgroundOpacity

    Shape {
      id: barBackgroundShape
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      enabled: false

      BarBackground {
        bar: root.bar
        shapeContainer: barBackgroundShape
        windowRoot: root.windowRoot
        backgroundColor: panelBackgroundColor
      }
    }

    NDropShadow {
      anchors.fill: parent
      source: barBackgroundShape
    }
  }
}
