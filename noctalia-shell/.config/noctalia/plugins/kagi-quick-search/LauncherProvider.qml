import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
    id: root

    // Plugin API provided by PluginService
    property var pluginApi: null

    // Provider metadata
    property string name: "Kagi Quick Search"
    property var launcher: null
    property bool handleSearch: false
    property string supportedLayouts: "single"
    property bool supportsAutoPaste: false
    property string emptyBrowsingMessage: "Enter a query"
    
    // State
    property string answer: ""
    property string answeredQuery: ""  // The query that the current answer is for
    property string pendingQuery: ""
    property bool isLoading: false
    property string errorMessage: ""
    property int loadingFrame: 0
    property var loadingFrames: ["-", "\\", "|", "/"]
    property string loadingSuffix: ""

    // Settings
    property string kagiSessionToken: pluginApi.pluginSettings.kagiSessionToken
    property int debounceMs: pluginApi.pluginSettings.debounceMs ?? 500

    function handleCommand(searchText) {
        return searchText.startsWith(">kagi");
    }

    function commands() {
        return [
            {
                "name": ">kagi",
                "description": "Get a quick answer to a query from Kagi",
                "icon": "search",
                "isTablerIcon": true,
                "isImage": false,
                "onActivate": function () {
                    launcher.setSearchText(">kagi ");
                }
            }
        ];
    }

    function fetchKagiAnswer(query: string, callback: var): void {
        internal.pendingCallback = callback
        internal.pendingQuery = query
        internal.collectedOutput = ""
        internal.process.running = true
    }

    function startSearch(query) {
        if (internal.process.running) {
            internal.cancelled = true;
            internal.process.running = false;
        }

        root.isLoading = true;
        root.errorMessage = "";
        root.answer = "";
        root.answeredQuery = "";
        root.pendingQuery = query;
        root.loadingFrame = 0;
        root.loadingSuffix = root.loadingFrames[0];

        Logger.i("Kagi Quick Search", `Searching for ${query}`)
        refreshLauncher(query);
        fetchKagiAnswer(query, function(error, result) {
            root.isLoading = false;
            root.loadingSuffix = "";
            if (error) {
                Logger.e("Kagi Quick Search", error)
                root.errorMessage = error;
                root.answer = "";
            } else {
                Logger.i("Kagi Quick Search", `Got answer: ${result.substring(0, 100)}...`)
                root.answer = result
                root.errorMessage = "";
            }
            root.answeredQuery = query

            // Force refresh by appending and removing a space
            if (root.launcher) {
                const originalText = ">kagi " + query
                root.launcher.setSearchText(originalText + " ")
                root.launcher.setSearchText(originalText)
            }
        })
    }

    function refreshLauncher(query) {
        if (!root.launcher) {
            return;
        }

        const originalText = ">kagi " + query;
        root.launcher.setSearchText(originalText + " ");
        root.launcher.setSearchText(originalText);
    }


    Timer {
        id: loadingTimer
        interval: 250
        repeat: true
        running: root.isLoading
        onTriggered: {
            if (!root.pendingQuery) {
                return;
            }
            root.loadingFrame = (root.loadingFrame + 1) % root.loadingFrames.length;
            root.loadingSuffix = root.loadingFrames[root.loadingFrame];
            refreshLauncher(root.pendingQuery);
        }
    }
    QtObject {
        id: internal
        
        property string pendingQuery: ""
        property var pendingCallback: null
        property string collectedOutput: ""
        property bool cancelled: false

        property Process process: Process {
            running: false

            command: [
                "bash", "-c",
                `curl -s 'https://kagi.com/mother/context?q=${encodeURIComponent(internal.pendingQuery)}' \
                    -X 'POST' \
                    -H 'accept: application/vnd.kagi.stream' \
                    -H 'accept-language: en-US,en;q=0.9' \
                    -H 'content-length: 0' \
                    -b 'kagi_session=${root.kagiSessionToken}' \
                    -H 'origin: https://kagi.com' \
                    -H 'referer: https://kagi.com/search?q=${encodeURIComponent(internal.pendingQuery)}' \
                    -H 'user-agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36' \
                    -H 'x-kagi-authorization: ${root.kagiSessionToken}' \
                    --output - | tail -1 | cut -d: -f2- | jq -r '.md' | sed 's/\\[\\^[0-9]*\\]//g; s/ \\././g'`
            ]

            stdout: SplitParser {
                onRead: data => {
                    internal.collectedOutput += data + "\n"
                }
            }

            onExited: function(exitCode, exitStatus) {
                Logger.i("Kagi Quick Search", "Search completed with exit code: " + exitCode)
                
                const result = internal.collectedOutput.trim()
                
                if (internal.pendingCallback) {
                    if (internal.cancelled) {
                        internal.cancelled = false;
                        internal.pendingCallback(null, "")
                    } else if (exitCode === 0) {
                        internal.pendingCallback(null, result)
                    } else {
                        internal.pendingCallback("Search failed with exit code: " + exitCode, null)
                    }
                    internal.pendingCallback = null
                }
            }
        }
    }

    function getResults(searchText) {
        if (!kagiSessionToken || kagiSessionToken === "") {
            return [
                {
                    "name": "Kagi Session Token not provided or invalid",
                    "description": "Please provide Kagi Session Token in the plugin settings",
                    "icon": "alert-circle",
                    "isTablerIcon": true,
                    "isImage": false
                }
            ];
        }

        if (!searchText.startsWith(">kagi")) {
            return [];
        }

        const query = searchText.slice(5).trim();

        // If we have an answer for this exact query, show it
        if (root.answer && root.answeredQuery === query) {
            return [
                {
                    "name": "Kagi Answer",
                    "description": root.answer,
                    "icon": "message-circle",
                    "isTablerIcon": true,
                    "isImage": false
                }
            ];
        }

        if (root.isLoading && query === root.pendingQuery) {
            return [
                {
                    "name": `Searching ${root.loadingSuffix}`,
                    "description": `Kagi is working on:\n${query}\n\nPlease wait...`,
                    "icon": "loader",
                    "isTablerIcon": true,
                    "isImage": false
                }
            ];
        }

        if (root.errorMessage && root.answeredQuery === query) {
            return [
                {
                    "name": "Kagi Error",
                    "description": root.errorMessage,
                    "icon": "alert-circle",
                    "isTablerIcon": true,
                    "isImage": false
                }
            ];
        }

        if (query.length > 10) {
            root.pendingQuery = query
            return [
                {
                    "name": "Press Enter to search",
                    "description": "Fetch a Kagi answer",
                    "icon": "search",
                    "isTablerIcon": true,
                    "isImage": false,
                    "onActivate": function () {
                        startSearch(query);
                    }
                }
            ];
        }

        return [
            {
                "name": "Type more to search",
                "description": "Enter at least 11 characters",
                "icon": "info-circle",
                "isTablerIcon": true,
                "isImage": false
            }
        ];
    }
}
