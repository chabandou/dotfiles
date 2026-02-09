import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Services.UI
import qs.Widgets

/**
* PanelBackgrounds - Unified Shape container for panel backgrounds only.
*
* Renders backgrounds for the currently open panel and the closing panel
* (for transitions). Uses the same shadow system as AllBackgrounds but
* excludes the bar background.
*/
Item {
  id: root

  // Reference to window root (for screen access)
  required property var windowRoot

  readonly property color panelBackgroundColor: Color.mSurface

  anchors.fill: parent

  // Panel backgrounds
  Item {
    anchors.fill: parent

    // Match the existing panel opacity behavior
    layer.enabled: true
    opacity: Settings.data.ui.panelBackgroundOpacity

    Shape {
      id: panelBackgroundsShape
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      enabled: false

      // Slot 0: Currently open/opening panel
      PanelBackground {
        assignedPanel: {
          var p = PanelService.backgroundSlotAssignments[0];
          return (p && p.screen === root.windowRoot.screen) ? p : null;
        }
        shapeContainer: panelBackgroundsShape
        defaultBackgroundColor: panelBackgroundColor
      }

      // Slot 1: Closing panel (during transitions)
      PanelBackground {
        assignedPanel: {
          var p = PanelService.backgroundSlotAssignments[1];
          return (p && p.screen === root.windowRoot.screen) ? p : null;
        }
        shapeContainer: panelBackgroundsShape
        defaultBackgroundColor: panelBackgroundColor
      }
    }

    NDropShadow {
      anchors.fill: parent
      source: panelBackgroundsShape
    }
  }
}
