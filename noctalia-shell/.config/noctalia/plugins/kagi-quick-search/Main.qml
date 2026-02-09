import QtQuick
import Quickshell.Io
import qs.Services.UI

Item {
  property var pluginApi: null

  IpcHandler {
    target: "plugin:kagi"
    function toggle() {
      pluginApi.withCurrentScreen(screen => {
                                    var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                                    if (!launcherPanel)
                                    return;
                                    var searchText = launcherPanel.searchText || "";
                                    var isInKagiSearch = searchText.startsWith(">kagi");
                                    if (!launcherPanel.isPanelOpen) {
                                      launcherPanel.open();
                                      launcherPanel.setSearchText(">kagi ");
                                    } else if (isInKagiSearch) {
                                      launcherPanel.close();
                                    } else {
                                      launcherPanel.setSearchText(">kagi ");
                                    }
                                  });
    }
  }
}
