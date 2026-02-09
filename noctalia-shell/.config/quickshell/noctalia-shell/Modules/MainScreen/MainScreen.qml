import QtQuick
import Quickshell
import Quickshell.Wayland
import "Backgrounds" as Backgrounds

import qs.Commons

import qs.Modules.Bar
import qs.Modules.Bar.Extras
import qs.Services.UI

/**
* MainScreen - Single PanelWindow per screen that manages the bar/backgrounds
*/
PanelWindow {
  id: root

  Component.onCompleted: {
    Logger.d("MainScreen", "Initialized for screen:", screen?.name, "- Dimensions:", screen?.width, "x", screen?.height, "- Position:", screen?.x, ",", screen?.y);
  }

  // Wayland
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "noctalia-background-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore // Don't reserve space - BarExclusionZone handles that
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  property bool isAnyPanelOpen: PanelService.openedPanel !== null

  color: "transparent"

  // Check if bar should be visible on this screen
  readonly property bool barShouldShow: {
    // Check global bar visibility (includes overview state)
    if (!BarService.effectivelyVisible)
      return false;

    // Check screen-specific configuration
    var monitors = Settings.data.bar.monitors || [];
    var screenName = screen?.name || "";

    // If no monitors specified, show on all screens
    // If monitors specified, only show if this screen is in the list
    return monitors.length === 0 || monitors.includes(screenName);
  }

  // Make everything click-through except bar
  mask: Region {
    id: clickableMask

    // Cover entire window (everything is masked/click-through)
    x: 0
    y: 0
    width: root.width
    height: root.height
    intersection: Intersection.Xor

    // Only include regions that are actually needed
    // panelRegions is handled by PanelService, bar is local to this screen
    regions: [barMaskRegion, backgroundMaskRegion]

    // Bar region - subtract bar area from mask (only if bar should be shown on this screen)
    Region {
      id: barMaskRegion

      readonly property bool isFramed: Settings.data.bar.barType === "framed"
      readonly property real barThickness: Style.barHeight
      readonly property real frameThickness: Settings.data.bar.frameThickness ?? 12
      readonly property string barPos: Settings.data.bar.position || "top"

      // Bar / Frame Mask
      Region {
        // Mode: Simple or Floating
        x: barPlaceholder.x
        y: barPlaceholder.y
        width: (!barMaskRegion.isFramed && root.barShouldShow) ? barPlaceholder.width : 0
        height: (!barMaskRegion.isFramed && root.barShouldShow) ? barPlaceholder.height : 0
        intersection: Intersection.Subtract
      }

      // Mode: Framed - 4 sides
      Region {
        // Top side
        Region {
          x: 0
          y: 0
          width: (barMaskRegion.isFramed && root.barShouldShow) ? root.width : 0
          height: (barMaskRegion.isFramed && root.barShouldShow) ? (barMaskRegion.barPos === "top" ? barMaskRegion.barThickness : barMaskRegion.frameThickness) : 0
          intersection: Intersection.Subtract
        }

        // Bottom side
        Region {
          x: 0
          y: (barMaskRegion.isFramed && root.barShouldShow) ? (root.height - (barMaskRegion.barPos === "bottom" ? barMaskRegion.barThickness : barMaskRegion.frameThickness)) : 0
          width: (barMaskRegion.isFramed && root.barShouldShow) ? root.width : 0
          height: (barMaskRegion.isFramed && root.barShouldShow) ? (barMaskRegion.barPos === "bottom" ? barMaskRegion.barThickness : barMaskRegion.frameThickness) : 0
          intersection: Intersection.Subtract
        }

        // Left side
        Region {
          x: 0
          y: 0
          width: (barMaskRegion.isFramed && root.barShouldShow) ? (barMaskRegion.barPos === "left" ? barMaskRegion.barThickness : barMaskRegion.frameThickness) : 0
          height: (barMaskRegion.isFramed && root.barShouldShow) ? root.height : 0
          intersection: Intersection.Subtract
        }

        // Right side
        Region {
          x: (barMaskRegion.isFramed && root.barShouldShow) ? (root.width - (barMaskRegion.barPos === "right" ? barMaskRegion.barThickness : barMaskRegion.frameThickness)) : 0
          width: (barMaskRegion.isFramed && root.barShouldShow) ? (barMaskRegion.barPos === "right" ? barMaskRegion.barThickness : barMaskRegion.frameThickness) : 0
          height: (barMaskRegion.isFramed && root.barShouldShow) ? root.height : 0
          intersection: Intersection.Subtract
        }
      }
    }

    // Background region for click-to-close - reactive sizing
    // Uses isAnyPanelOpen so clicking on any screen's background closes the panel
    Region {
      id: backgroundMaskRegion
      x: 0
      y: 0
      width: root.isAnyPanelOpen ? root.width : 0
      height: root.isAnyPanelOpen ? root.height : 0
      intersection: Intersection.Subtract
    }
  }

  // --------------------------------------
  // Container for all UI elements
  Item {
    id: container
    width: root.width
    height: root.height

    // Bar backgrounds container (panels are rendered in the overlay window)
    Backgrounds.BarBackgrounds {
      id: barBackgrounds
      anchors.fill: parent
      bar: barPlaceholder.barItem || null
      windowRoot: root
      z: 0 // Behind all content
    }

    // Background MouseArea for closing panels when clicking outside
    // Uses isAnyPanelOpen so clicking on any screen's background closes the panel
    MouseArea {
      anchors.fill: parent
      enabled: root.isAnyPanelOpen
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      // Keep wheel-based bar interactions working while a panel is open.
      // If the wheel event happens over the bar geometry, pass it through.
      onWheel: wheel => {
                 if (!Settings.data.general.allowHoverWidgetWheelControl) {
                   wheel.accepted = true;
                   return;
                 }
                 var globalX = (root.screen?.x || 0) + wheel.x;
                 var globalY = (root.screen?.y || 0) + wheel.y;
                 if (PanelService.handleHoverWidgetWheel(wheel.angleDelta.y, globalX, globalY)) {
                   wheel.accepted = true;
                   return;
                 }
                 var inBar = root.barShouldShow
                             && wheel.x >= barPlaceholder.x
                             && wheel.x <= (barPlaceholder.x + barPlaceholder.width)
                             && wheel.y >= barPlaceholder.y
                             && wheel.y <= (barPlaceholder.y + barPlaceholder.height);
                 wheel.accepted = !inBar;
               }
      onClicked: mouse => {
                   if (PanelService.openedPanel) {
                     PanelService.openedPanel.close();
                   }
                 }
      z: 0 // Behind panels and bar
    }

    // ----------------------------------------------
    // Bar background placeholder - just for background positioning (actual bar content is in BarContentWindow)
    Item {
      id: barPlaceholder

      // Expose self as barItem for AllBackgrounds compatibility
      readonly property var barItem: barPlaceholder

      // Screen reference
      property ShellScreen screen: root.screen

      // Bar background positioning properties (per-screen)
      readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name)
      readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
      readonly property bool isFramed: Settings.data.bar.barType === "framed"
      readonly property real frameThickness: Settings.data.bar.frameThickness ?? 12
      readonly property bool barFloating: Settings.data.bar.floating || false
      readonly property real barMarginH: barFloating ? Math.floor(Settings.data.bar.marginHorizontal) : 0
      readonly property real barMarginV: barFloating ? Math.floor(Settings.data.bar.marginVertical) : 0
      readonly property real barHeight: Style.getBarHeightForScreen(screen?.name)

      // Expose bar dimensions directly on this Item for BarBackground
      // Use screen dimensions directly
      x: {
        if (barPosition === "right")
          return screen.width - barHeight - barMarginH;
        if (isFramed && !barIsVertical)
          return frameThickness;
        return barMarginH;
      }
      y: {
        if (barPosition === "bottom")
          return screen.height - barHeight - barMarginV;
        if (isFramed && barIsVertical)
          return frameThickness;
        return barMarginV;
      }
      width: {
        if (barIsVertical) {
          return barHeight;
        }
        if (isFramed)
          return screen.width - frameThickness * 2;
        return screen.width - barMarginH * 2;
      }
      height: {
        if (!barIsVertical) {
          return barHeight;
        }
        if (isFramed)
          return screen.height - frameThickness * 2;
        return screen.height - barMarginV * 2;
      }

      // Corner states (same as Bar.qml)
      readonly property int topLeftCornerState: {
        if (barFloating)
          return 0;
        if (barPosition === "top")
          return -1;
        if (barPosition === "left")
          return -1;
        if (Settings.data.bar.outerCorners && (barPosition === "bottom" || barPosition === "right")) {
          return barIsVertical ? 1 : 2;
        }
        return -1;
      }

      readonly property int topRightCornerState: {
        if (barFloating)
          return 0;
        if (barPosition === "top")
          return -1;
        if (barPosition === "right")
          return -1;
        if (Settings.data.bar.outerCorners && (barPosition === "bottom" || barPosition === "left")) {
          return barIsVertical ? 1 : 2;
        }
        return -1;
      }

      readonly property int bottomLeftCornerState: {
        if (barFloating)
          return 0;
        if (barPosition === "bottom")
          return -1;
        if (barPosition === "left")
          return -1;
        if (Settings.data.bar.outerCorners && (barPosition === "top" || barPosition === "right")) {
          return barIsVertical ? 1 : 2;
        }
        return -1;
      }

      readonly property int bottomRightCornerState: {
        if (barFloating)
          return 0;
        if (barPosition === "bottom")
          return -1;
        if (barPosition === "right")
          return -1;
        if (Settings.data.bar.outerCorners && (barPosition === "top" || barPosition === "left")) {
          return barIsVertical ? 1 : 2;
        }
        return -1;
      }
    }

    /**
    *  Screen Corners
    */
    ScreenCorners {}
  }

}
