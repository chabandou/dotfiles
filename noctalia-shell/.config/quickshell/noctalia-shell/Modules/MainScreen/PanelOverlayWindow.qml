import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "Backgrounds" as Backgrounds

import qs.Commons

// Panels
import qs.Modules.Panels.Audio
import qs.Modules.Panels.Battery
import qs.Modules.Panels.Bluetooth
import qs.Modules.Panels.Brightness
import qs.Modules.Panels.Changelog
import qs.Modules.Panels.Clock
import qs.Modules.Panels.ControlCenter
import qs.Modules.Panels.Launcher
import qs.Modules.Panels.Media
import qs.Modules.Panels.Network
import qs.Modules.Panels.NotificationHistory
import qs.Modules.Panels.Plugins
import qs.Modules.Panels.SessionMenu
import qs.Modules.Panels.Settings
import qs.Modules.Panels.SetupWizard
import qs.Modules.Panels.SystemStats
import qs.Modules.Panels.Tray
import qs.Modules.Panels.Wallpaper

import qs.Services.Compositor
import qs.Services.UI

/**
* PanelOverlayWindow - Overlay window that hosts panels above fullscreen apps.
*/
PanelWindow {
  id: root

  Component.onCompleted: {
    Logger.d("PanelOverlayWindow", "Initialized for screen:", screen?.name);
  }

  // Wayland
  WlrLayershell.layer: CompositorService.isHyprland ? WlrLayer.Overlay : WlrLayer.Top
  WlrLayershell.namespace: "noctalia-panel-overlay-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore
  WlrLayershell.keyboardFocus: {
    // No panel open anywhere: no keyboard focus needed
    if (!root.isAnyPanelOpen) {
      return WlrKeyboardFocus.None;
    }
    // Panel open on THIS screen: use panel's preferred focus mode
    if (root.isPanelOpen) {
      // Hyprland's Exclusive captures ALL input globally (including pointer),
      // preventing click-to-close from working on other monitors.
      // Workaround: briefly use Exclusive when panel opens (for text input focus),
      // then switch to OnDemand (for click-to-close on other screens).
      if (CompositorService.isHyprland) {
        return PanelService.isInitializingKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand;
      }
      return PanelService.openedPanel.exclusiveKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand;
    }
    // Panel open on ANOTHER screen: OnDemand allows receiving pointer events for click-to-close
    return WlrKeyboardFocus.OnDemand;
  }

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Keep the overlay window mapped to avoid compositor layer "slide" animations on show.
  // We control visibility via opacity/mask instead.
  visible: true

  // Desktop dimming when panels are open
  property real dimmerOpacity: Settings.data.general.dimmerOpacity ?? 0.8
  property bool isPanelOpen: (PanelService.openedPanel !== null) && (PanelService.openedPanel.screen === screen)
  property bool isPanelClosing: (PanelService.openedPanel !== null) && PanelService.openedPanel.isClosing
  property bool isAnyPanelOpen: PanelService.openedPanel !== null

  color: {
    if (dimmerOpacity > 0 && isPanelOpen && !isPanelClosing) {
      return Qt.alpha(Color.mShadow, dimmerOpacity);
    }
    return "transparent";
  }

  Behavior on color {
    enabled: !PanelService.closedImmediately
    ColorAnimation {
      duration: isPanelClosing ? Style.animationFaster : Style.animationNormal
      easing.type: Easing.OutQuad
    }
  }

  // Reset closedImmediately flag after color change is applied
  onColorChanged: {
    if (PanelService.closedImmediately) {
      PanelService.closedImmediately = false;
    }
  }

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
  // Container for panel UI elements
  Item {
    id: container
    // Skip rendering when no panels are open to reduce GPU work.
    visible: root.isAnyPanelOpen
    width: root.width
    height: root.height

    // Panel backgrounds + shadows
    Backgrounds.PanelBackgrounds {
      id: panelBackgrounds
      anchors.fill: parent
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
      z: 0 // Behind panels
    }

    // ---------------------------------------
    // All panels always exist
    // ---------------------------------------
    AudioPanel {
      id: audioPanel
      objectName: "audioPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    MediaPlayerPanel {
      id: mediaPlayerPanel
      objectName: "mediaPlayerPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    BatteryPanel {
      id: batteryPanel
      objectName: "batteryPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    BluetoothPanel {
      id: bluetoothPanel
      objectName: "bluetoothPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    BrightnessPanel {
      id: brightnessPanel
      objectName: "brightnessPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    ControlCenterPanel {
      id: controlCenterPanel
      objectName: "controlCenterPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    ChangelogPanel {
      id: changelogPanel
      objectName: "changelogPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    ClockPanel {
      id: clockPanel
      objectName: "clockPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    Launcher {
      id: launcherPanel
      objectName: "launcherPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    NotificationHistoryPanel {
      id: notificationHistoryPanel
      objectName: "notificationHistoryPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    SessionMenu {
      id: sessionMenuPanel
      objectName: "sessionMenuPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    SettingsPanel {
      id: settingsPanel
      objectName: "settingsPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    SetupWizard {
      id: setupWizardPanel
      objectName: "setupWizardPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    TrayDrawerPanel {
      id: trayDrawerPanel
      objectName: "trayDrawerPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    WallpaperPanel {
      id: wallpaperPanel
      objectName: "wallpaperPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    NetworkPanel {
      id: networkPanel
      objectName: "networkPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    SystemStatsPanel {
      id: systemStatsPanel
      objectName: "systemStatsPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    // ----------------------------------------------
    // Plugin panel slots
    // ----------------------------------------------
    PluginPanelSlot {
      id: pluginPanel1
      objectName: "pluginPanel1-" + (root.screen?.name || "unknown")
      screen: root.screen
      slotNumber: 1
    }

    PluginPanelSlot {
      id: pluginPanel2
      objectName: "pluginPanel2-" + (root.screen?.name || "unknown")
      screen: root.screen
      slotNumber: 2
    }

    // ----------------------------------------------
    // Bar background placeholder - just for background positioning (used for mask)
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
    }
  }

  // ========================================
  // Centralized Keyboard Shortcuts
  // ========================================
  // These shortcuts delegate to the opened panel's handler functions
  // Panels can implement: onEscapePressed, onTabPressed, onBackTabPressed,
  // onUpPressed, onDownPressed, onReturnPressed, etc...
  Shortcut {
    sequence: "Escape"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onEscapePressed !== undefined)
    onActivated: PanelService.openedPanel.onEscapePressed()
  }

  Shortcut {
    sequence: "Tab"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onTabPressed !== undefined)
    onActivated: PanelService.openedPanel.onTabPressed()
  }

  Shortcut {
    sequence: "Backtab"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onBackTabPressed !== undefined)
    onActivated: PanelService.openedPanel.onBackTabPressed()
  }

  Shortcut {
    sequence: "Up"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onUpPressed !== undefined)
    onActivated: PanelService.openedPanel.onUpPressed()
  }

  Shortcut {
    sequence: "Down"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onDownPressed !== undefined)
    onActivated: PanelService.openedPanel.onDownPressed()
  }

  Shortcut {
    sequence: "Return"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onReturnPressed !== undefined)
    onActivated: PanelService.openedPanel.onReturnPressed()
  }

  Shortcut {
    sequence: "Enter"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onEnterPressed !== undefined)
    onActivated: PanelService.openedPanel.onEnterPressed()
  }

  Shortcut {
    sequence: "Left"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onLeftPressed !== undefined)
    onActivated: PanelService.openedPanel.onLeftPressed()
  }

  Shortcut {
    sequence: "Right"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onRightPressed !== undefined)
    onActivated: PanelService.openedPanel.onRightPressed()
  }

  Shortcut {
    sequence: "Home"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onHomePressed !== undefined)
    onActivated: PanelService.openedPanel.onHomePressed()
  }

  Shortcut {
    sequence: "End"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onEndPressed !== undefined)
    onActivated: PanelService.openedPanel.onEndPressed()
  }

  Shortcut {
    sequence: "PgUp"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onPageUpPressed !== undefined)
    onActivated: PanelService.openedPanel.onPageUpPressed()
  }

  Shortcut {
    sequence: "PgDown"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onPageDownPressed !== undefined)
    onActivated: PanelService.openedPanel.onPageDownPressed()
  }

  Shortcut {
    sequence: "Ctrl+H"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onCtrlHPressed !== undefined)
    onActivated: PanelService.openedPanel.onCtrlHPressed()
  }

  Shortcut {
    sequence: "Ctrl+J"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onCtrlJPressed !== undefined)
    onActivated: PanelService.openedPanel.onCtrlJPressed()
  }

  Shortcut {
    sequence: "Ctrl+K"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onCtrlKPressed !== undefined)
    onActivated: PanelService.openedPanel.onCtrlKPressed()
  }

  Shortcut {
    sequence: "Ctrl+L"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onCtrlLPressed !== undefined)
    onActivated: PanelService.openedPanel.onCtrlLPressed()
  }

  Shortcut {
    sequence: "Ctrl+N"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onCtrlNPressed !== undefined)
    onActivated: PanelService.openedPanel.onCtrlNPressed()
  }

  Shortcut {
    sequence: "Ctrl+P"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onCtrlPPressed !== undefined)
    onActivated: PanelService.openedPanel.onCtrlPPressed()
  }

  Shortcut {
    sequence: "1"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(1)
  }

  Shortcut {
    sequence: "2"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(2)
  }

  Shortcut {
    sequence: "3"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(3)
  }

  Shortcut {
    sequence: "4"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(4)
  }

  Shortcut {
    sequence: "5"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(5)
  }

  Shortcut {
    sequence: "6"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(6)
  }

  Shortcut {
    sequence: "7"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(7)
  }

  Shortcut {
    sequence: "8"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(8)
  }

  Shortcut {
    sequence: "9"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(9)
  }
}
