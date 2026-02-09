pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Services.Media

Singleton {
  id: root

  // A ref. to the lockScreen, so it's accessible from anywhere.
  property var lockScreen: null

  // Panels
  property var registeredPanels: ({})
  property var openedPanel: null
  property var closingPanel: null
  property bool closedImmediately: false
  // Brief window after panel opens where Exclusive keyboard is allowed on Hyprland
  // This allows text inputs to receive focus, then switches to OnDemand for click-to-close
  property bool isInitializingKeyboard: false
  // Hover-open state for bar widgets that map to panels (launcher intentionally excluded).
  property var hoverManagedPanel: null
  property var hoverSourceItem: null
  property string hoverSourceWidgetId: ""
  property var hoverSourceScreen: null
  property bool hoverSourceHovered: false
  property bool hoverPanelHovered: false
  // Prevent immediate reopen loops until pointer leaves the source widget once.
  property bool hoverReentryRequired: false
  property var hoverReentrySource: null
  property bool hoverCursorCheckPending: false
  property string hoverCursorCheckMode: ""
  property var hoverCursorCheckPanel: null
  property var hoverCursorCheckSource: null
  // Hover timing tuning for responsiveness.
  property int hoverCloseDelayMs: 110
  property int hoverPollIntervalMs: 70
  signal willOpen
  signal didClose

  // Background slot assignments for dynamic panel background rendering
  // Slot 0: currently opening/open panel, Slot 1: closing panel
  property var backgroundSlotAssignments: [null, null]
  signal slotAssignmentChanged(int slotIndex, var panel)

  function assignToSlot(slotIndex, panel) {
    if (backgroundSlotAssignments[slotIndex] !== panel) {
      var newAssignments = backgroundSlotAssignments.slice();
      newAssignments[slotIndex] = panel;
      backgroundSlotAssignments = newAssignments;
      slotAssignmentChanged(slotIndex, panel);
    }
  }

  // Popup menu windows (one per screen) - used for both tray menus and context menus
  property var popupMenuWindows: ({})
  signal popupMenuWindowRegistered(var screen)

  // Close hovered panel only after the pointer has left both source widget and panel overlay.
  Timer {
    id: hoverCloseTimer
    interval: root.hoverCloseDelayMs
    repeat: false
    onTriggered: {
      if (!root.hoverManagedPanel || root.openedPanel !== root.hoverManagedPanel) {
        root.clearHoverTracking();
        return;
      }
      if (root.hoverManagedPanel.isClosing) {
        return;
      }

      if (CompositorService.isHyprland && !hyprCursorPosProcess.running) {
        root.hoverCursorCheckPending = true;
        root.hoverCursorCheckMode = "close";
        root.hoverCursorCheckPanel = root.hoverManagedPanel;
        root.hoverCursorCheckSource = root.hoverSourceItem;
        hyprCursorPosProcess.running = true;
        return;
      }

      var shouldClose = !root.hoverSourceHovered && !root.hoverPanelHovered;
      if (shouldClose) {
        root.closeHoverManagedPanel();
        root.clearHoverTracking();
      }
    }
  }

  // Poll real cursor position on Hyprland to recover from missed hover enter/exit events.
  Timer {
    id: hoverPollTimer
    interval: root.hoverPollIntervalMs
    repeat: true
    running: false
    onTriggered: {
      if (!CompositorService.isHyprland || !root.hoverManagedPanel || root.openedPanel !== root.hoverManagedPanel || root.hoverManagedPanel.isClosing) {
        stop();
        return;
      }
      if (hyprCursorPosProcess.running) {
        return;
      }
      root.hoverCursorCheckPending = true;
      root.hoverCursorCheckMode = "poll";
      root.hoverCursorCheckPanel = root.hoverManagedPanel;
      root.hoverCursorCheckSource = root.hoverSourceItem;
      hyprCursorPosProcess.running = true;
    }
  }

  function closeHoverManagedPanel() {
    var sourceItem = root.hoverSourceItem;
    if (root.openedPanel && root.openedPanel === root.hoverManagedPanel && !root.openedPanel.isClosing) {
      root.openedPanel.close();
    }
    root.hoverReentryRequired = true;
    root.hoverReentrySource = sourceItem;
  }

  function clearHoverTracking() {
    hoverCloseTimer.stop();
    hoverPollTimer.stop();
    hoverCursorCheckPending = false;
    hoverCursorCheckMode = "";
    hoverCursorCheckPanel = null;
    hoverCursorCheckSource = null;
    if (hyprCursorPosProcess.running) {
      hyprCursorPosProcess.running = false;
    }
    root.hoverManagedPanel = null;
    root.hoverSourceItem = null;
    root.hoverSourceWidgetId = "";
    root.hoverSourceScreen = null;
    root.hoverSourceHovered = false;
    root.hoverPanelHovered = false;
  }

  function sourceItemContainsPoint(item, x, y) {
    if (!item || !item.visible || item.width <= 0 || item.height <= 0 || typeof item.mapToGlobal !== "function") {
      return false;
    }
    var topLeft = item.mapToGlobal(0, 0);
    return x >= topLeft.x && x <= (topLeft.x + item.width) && y >= topLeft.y && y <= (topLeft.y + item.height);
  }

  function panelContainsPoint(panel, x, y) {
    if (!panel || !panel.panelRegion || !panel.panelRegion.visible || panel.panelRegion.width <= 0 || panel.panelRegion.height <= 0 || typeof panel.panelRegion.mapToGlobal !== "function") {
      return false;
    }
    var topLeft = panel.panelRegion.mapToGlobal(0, 0);
    return x >= topLeft.x && x <= (topLeft.x + panel.panelRegion.width) && y >= topLeft.y && y <= (topLeft.y + panel.panelRegion.height);
  }

  // Fallback handling for wheel-based icon adjustments while hover-open panels are active.
  // On some compositors/layer combinations, wheel events do not reach bar widgets beneath the overlay.
  function handleHoverWidgetWheel(deltaY, globalX, globalY) {
    if (!Settings.data.general.allowHoverWidgetWheelControl) {
      return false;
    }
    if (!root.hoverManagedPanel || root.openedPanel !== root.hoverManagedPanel || root.hoverManagedPanel.isClosing) {
      return false;
    }
    if (!root.hoverSourceItem || root.hoverSourceWidgetId === "" || !isFinite(deltaY) || deltaY === 0) {
      return false;
    }
    if (!root.sourceItemContainsPoint(root.hoverSourceItem, globalX, globalY)) {
      return false;
    }

    switch (root.hoverSourceWidgetId) {
    case "Volume":
      if (deltaY > 0)
        AudioService.increaseVolume();
      else
        AudioService.decreaseVolume();
      return true;
    case "Microphone":
      if (deltaY > 0)
        AudioService.increaseInputVolume();
      else
        AudioService.decreaseInputVolume();
      return true;
    case "Brightness":
      var monitor = BrightnessService.getMonitorForScreen(root.hoverSourceScreen || root.hoverManagedPanel.screen);
      if (!monitor || !monitor.brightnessControlAvailable) {
        return false;
      }
      if (deltaY > 0)
        monitor.increaseBrightness();
      else
        monitor.decreaseBrightness();
      return true;
    default:
      return false;
    }
  }

  Process {
    id: hyprCursorPosProcess
    running: false
    command: ["hyprctl", "cursorpos", "-j"]
    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        hyprCursorPosProcess.accumulatedOutput += line;
      }
    }

    onExited: function (exitCode) {
      var output = hyprCursorPosProcess.accumulatedOutput;
      hyprCursorPosProcess.accumulatedOutput = "";

      if (!root.hoverCursorCheckPending) {
        return;
      }

      var mode = root.hoverCursorCheckMode;
      var panel = root.hoverCursorCheckPanel;
      var source = root.hoverCursorCheckSource;
      root.hoverCursorCheckPending = false;
      root.hoverCursorCheckMode = "";
      root.hoverCursorCheckPanel = null;
      root.hoverCursorCheckSource = null;

      if (!panel || root.hoverManagedPanel !== panel || root.openedPanel !== panel || panel.isClosing) {
        return;
      }

      var inSource = root.hoverSourceHovered;
      var inPanel = root.hoverPanelHovered;

      if (exitCode === 0 && output && output.trim().length > 0) {
        try {
          var cursor = JSON.parse(output);
          inSource = root.sourceItemContainsPoint(source, cursor.x, cursor.y);
          inPanel = root.panelContainsPoint(panel, cursor.x, cursor.y);
        } catch (e) {
          Logger.w("PanelService", "Failed to parse hyprctl cursor position:", e);
        }
      }

      root.hoverSourceHovered = inSource;
      root.hoverPanelHovered = inPanel;

      if (mode === "poll") {
        if (!inSource && !inPanel) {
          if (!hoverCloseTimer.running) {
            hoverCloseTimer.restart();
          }
        } else {
          hoverCloseTimer.stop();
        }
        return;
      }

      if (!inSource && !inPanel) {
        root.closeHoverManagedPanel();
        root.clearHoverTracking();
      }
    }
  }

  function panelNameForBarWidget(widgetId) {
    switch (widgetId) {
    case "Volume":
    case "Microphone":
      return "audioPanel";
    case "Battery":
      return "batteryPanel";
    case "Bluetooth":
      return "bluetoothPanel";
    case "Brightness":
      return "brightnessPanel";
    case "Clock":
      return "clockPanel";
    case "ControlCenter":
      return "controlCenterPanel";
    case "MediaMini":
      return "mediaPlayerPanel";
    case "Network":
      return "networkPanel";
    case "NotificationHistory":
      return "notificationHistoryPanel";
    case "SessionMenu":
      return "sessionMenuPanel";
    case "SystemMonitor":
      return "systemStatsPanel";
    case "Tray":
      return "trayDrawerPanel";
    case "WallpaperSelector":
      return "wallpaperPanel";
    default:
      return "";
    }
  }

  function updateHoverWidgetState(widgetId, screen, anchorItem, hovered) {
    var panelName = panelNameForBarWidget(widgetId);
    if (panelName === "" || !screen || !anchorItem)
      return;

    var panel = getPanel(panelName, screen);
    if (!panel)
      return;

    if (hovered) {
      if (root.hoverReentryRequired && root.hoverReentrySource === anchorItem) {
        return;
      }
      if (root.hoverReentryRequired && root.hoverReentrySource !== anchorItem) {
        root.hoverReentryRequired = false;
        root.hoverReentrySource = null;
      }

      root.hoverSourceItem = anchorItem;
      root.hoverSourceWidgetId = widgetId;
      root.hoverSourceScreen = screen;
      root.hoverSourceHovered = true;
      root.hoverPanelHovered = false;

      if (root.hoverManagedPanel && root.hoverManagedPanel !== panel && root.openedPanel === root.hoverManagedPanel && !root.hoverManagedPanel.isClosing) {
        root.hoverManagedPanel.close();
      }

      root.hoverManagedPanel = panel;
      hoverCloseTimer.stop();
      if (CompositorService.isHyprland && !hoverPollTimer.running) {
        hoverPollTimer.start();
      }

      if (root.openedPanel !== panel) {
        panel.open(anchorItem, widgetId);
      }
      return;
    }

    if (root.hoverManagedPanel === panel && root.hoverSourceItem === anchorItem) {
      root.hoverSourceHovered = false;
      if (root.openedPanel === panel && !panel.isClosing) {
        hoverCloseTimer.restart();
      }
    }

    if (root.hoverReentryRequired && root.hoverReentrySource === anchorItem) {
      root.hoverReentryRequired = false;
      root.hoverReentrySource = null;
    }
  }

  function setHoverPanelHovered(panel, hovered) {
    if (!panel || root.hoverManagedPanel !== panel)
      return;

    root.hoverPanelHovered = hovered;
    if (hovered) {
      hoverCloseTimer.stop();
    } else if (root.openedPanel === panel && !panel.isClosing) {
      hoverCloseTimer.restart();
    }
  }

  // Register this panel (called after panel is loaded)
  function registerPanel(panel) {
    registeredPanels[panel.objectName] = panel;
    Logger.d("PanelService", "Registered panel:", panel.objectName);
  }

  // Register popup menu window for a screen
  function registerPopupMenuWindow(screen, window) {
    if (!screen || !window)
      return;
    var key = screen.name;
    popupMenuWindows[key] = window;
    Logger.d("PanelService", "Registered popup menu window for screen:", key);
    popupMenuWindowRegistered(screen);
  }

  // Get popup menu window for a screen
  function getPopupMenuWindow(screen) {
    if (!screen)
      return null;
    return popupMenuWindows[screen.name] || null;
  }

  // Show a context menu with proper handling for all compositors
  function showContextMenu(contextMenu, anchorItem, screen) {
    if (!contextMenu || !anchorItem)
      return;

    // Close any previously opened context menu first
    closeContextMenu(screen);

    var popupMenuWindow = getPopupMenuWindow(screen);
    if (popupMenuWindow) {
      popupMenuWindow.showContextMenu(contextMenu);
      contextMenu.openAtItem(anchorItem, screen);
    }
  }

  // Close any open context menu or popup menu window
  function closeContextMenu(screen) {
    var popupMenuWindow = getPopupMenuWindow(screen);
    if (popupMenuWindow && popupMenuWindow.visible) {
      popupMenuWindow.close();
    }
  }

  // Show a tray menu with proper handling for all compositors
  // Returns true if menu was shown successfully
  function showTrayMenu(screen, trayItem, trayMenu, anchorItem, menuX, menuY, widgetSection, widgetIndex) {
    if (!trayItem || !trayMenu || !anchorItem)
      return false;

    // Close any previously opened menu first
    closeContextMenu(screen);

    trayMenu.trayItem = trayItem;
    trayMenu.widgetSection = widgetSection;
    trayMenu.widgetIndex = widgetIndex;

    var popupMenuWindow = getPopupMenuWindow(screen);
    if (popupMenuWindow) {
      popupMenuWindow.open();
      trayMenu.showAt(anchorItem, menuX, menuY);
    } else {
      return false;
    }
    return true;
  }

  // Close tray menu
  function closeTrayMenu(screen) {
    var popupMenuWindow = getPopupMenuWindow(screen);
    if (popupMenuWindow) {
      // This closes both the window and calls hideMenu on the tray menu
      popupMenuWindow.close();
    }
  }

  // Returns a panel (loads it on-demand if not yet loaded)
  function getPanel(name, screen) {
    if (!screen) {
      Logger.d("PanelService", "missing screen for getPanel:", name);
      // If no screen specified, return the first matching panel
      for (var key in registeredPanels) {
        if (key.startsWith(name + "-")) {
          return registeredPanels[key];
        }
      }
      return null;
    }

    var panelKey = `${name}-${screen.name}`;

    // Check if panel is already loaded
    if (registeredPanels[panelKey]) {
      return registeredPanels[panelKey];
    }

    Logger.w("PanelService", "Panel not found:", panelKey);
    return null;
  }

  // Check if a panel exists
  function hasPanel(name) {
    return name in registeredPanels;
  }

  // Check if panels can be shown on a given screen (has bar enabled or allowPanelsOnScreenWithoutBar)
  function canShowPanelsOnScreen(screen) {
    const name = screen?.name || "";
    const monitors = Settings.data.bar.monitors || [];
    const allowPanelsOnScreenWithoutBar = Settings.data.general.allowPanelsOnScreenWithoutBar;
    return allowPanelsOnScreenWithoutBar || monitors.length === 0 || monitors.includes(name);
  }

  // Find a screen that can show panels
  function findScreenForPanels() {
    for (let i = 0; i < Quickshell.screens.length; i++) {
      if (canShowPanelsOnScreen(Quickshell.screens[i])) {
        return Quickshell.screens[i];
      }
    }
    return null;
  }

  // Timer to switch from Exclusive to OnDemand keyboard focus on Hyprland
  Timer {
    id: keyboardInitTimer
    interval: 100
    repeat: false
    onTriggered: {
      root.isInitializingKeyboard = false;
    }
  }

  // Helper to keep only one panel open at any time
  function willOpenPanel(panel) {
    if (root.hoverManagedPanel && panel !== root.hoverManagedPanel) {
      clearHoverTracking();
    }

    if (openedPanel && openedPanel !== panel) {
      // Move current panel to closing slot before closing it
      closingPanel = openedPanel;
      assignToSlot(1, closingPanel);
      openedPanel.close();
    }

    // Assign new panel to open slot
    openedPanel = panel;
    assignToSlot(0, panel);

    // Start keyboard initialization period (for Hyprland workaround)
    if (panel.exclusiveKeyboard) {
      isInitializingKeyboard = true;
      keyboardInitTimer.restart();
    }

    // emit signal
    willOpen();
  }

  function closedPanel(panel) {
    if (root.hoverManagedPanel === panel) {
      clearHoverTracking();
    }

    if (openedPanel && openedPanel === panel) {
      openedPanel = null;
      assignToSlot(0, null);
    }

    if (closingPanel && closingPanel === panel) {
      closingPanel = null;
      assignToSlot(1, null);
    }

    // Reset keyboard init state
    isInitializingKeyboard = false;
    keyboardInitTimer.stop();

    // emit signal
    didClose();
  }

  // Close panels when compositor overview opens (if setting is enabled)
  Connections {
    target: CompositorService
    enabled: Settings.data.bar.hideOnOverview

    function onOverviewActiveChanged() {
      if (CompositorService.overviewActive && root.openedPanel) {
        root.openedPanel.close();
      }
    }
  }
}
