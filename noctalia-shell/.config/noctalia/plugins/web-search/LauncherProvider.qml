import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
    id: root

    property var pluginApi: null

    property string name: "Web Search"
    property var launcher: null
    property bool handleSearch: false
    property string supportedLayouts: "single"
    property bool supportsAutoPaste: false
    property string emptyBrowsingMessage: "Enter a query"

    function toLocalPath(url) {
        const raw = url.toString();
        if (raw.startsWith("file://")) {
            return decodeURIComponent(raw.slice(7));
        }
        return raw;
    }

    property string commandPrefix: pluginApi ? (pluginApi.pluginSettings.commandPrefix ?? ">web") : ">web"
    property int minQueryLength: pluginApi ? (pluginApi.pluginSettings.minQueryLength ?? 3) : 3
    property int maxSources: pluginApi ? (pluginApi.pluginSettings.maxSources ?? 3) : 3
    property string ollamaModel: pluginApi ? (pluginApi.pluginSettings.ollamaModel ?? "qwen2.5:1.5b-instruct") : "qwen2.5:1.5b-instruct"
    property string pythonPath: pluginApi ? (pluginApi.pluginSettings.pythonPath ?? "python3") : "python3"
    property string outputFile: pluginApi ? (pluginApi.pluginSettings.outputFile ?? "~/.cache/noctalia/web-search-last.json") : "~/.cache/noctalia/web-search-last.json"
    property string scriptPath: toLocalPath(Qt.resolvedUrl("summarize_web.py"))

    property string lastQuery: ""
    property string lastSummary: ""
    property string lastTimings: ""
    property bool isLoading: false
    property string errorMessage: ""
    property int maxRuntimeMs: 120000

    function handleCommand(searchText) {
        return searchText.startsWith(commandPrefix);
    }

    function sanitizedPythonPath() {
        return pythonPath.replace(/[\r\n\t]/g, "");
    }

    function commands() {
        return [
            {
                "name": commandPrefix,
                "description": "Search the web with local summary",
                "icon": "search",
                "isTablerIcon": true,
                "isImage": false,
                "onActivate": function () {
                    if (launcher) {
                        launcher.setSearchText(commandPrefix + " ");
                    }
                }
            }
        ];
    }

    function browserSearchUrl(query) {
        return `https://duckduckgo.com/?q=${encodeURIComponent(query)}`;
    }

    function openUrl(url) {
        if (url && url.length > 0) {
            Qt.openUrlExternally(url);
        }
        if (launcher) {
            launcher.close();
        }
    }

    function clampSummary(text) {
        const maxLen = 500;
        if (text.length > maxLen) {
            return text.slice(0, maxLen - 1) + "…";
        }
        return text;
    }

    function formatMs(ms) {
        if (ms === undefined || ms === null) {
            return "";
        }
        return `${(ms / 1000).toFixed(1)}s`;
    }

    function formatTimings(timings) {
        if (!timings) {
            return "";
        }
        const parts = [];
        if (timings.search !== undefined) parts.push(`DDG ${formatMs(timings.search)}`);
        if (timings.fetch !== undefined) parts.push(`Pages ${formatMs(timings.fetch)}`);
        if (timings.ollama !== undefined) parts.push(`Ollama ${formatMs(timings.ollama)}`);
        if (timings.total !== undefined) parts.push(`Total ${formatMs(timings.total)}`);
        return parts.join(" • ");
    }

    QtObject {
        id: internal

        property string pendingQuery: ""
        property string nextQuery: ""
        property bool restartAfterStop: false
        property string collectedOutput: ""
        property string collectedError: ""
        property int requestId: 0
        property int timeoutRequestId: 0
        property bool timedOut: false

        function startSearch(query) {
            pendingQuery = query;
            collectedOutput = "";
            collectedError = "";
            root.isLoading = true;
            root.errorMessage = "";
            root.lastSummary = "";
            root.lastTimings = "";
            timedOut = false;
            requestId += 1;
            timeoutRequestId = requestId;

            if (process.running) {
                restartAfterStop = true;
                nextQuery = query;
                process.running = false;
                return;
            }

            process.running = true;
            timeoutTimer.restart();
            refreshLauncher(query);
        }

        function refreshLauncher(query) {
            if (!root.launcher) {
                return;
            }
            const originalText = root.commandPrefix + " " + query;
            root.launcher.setSearchText(originalText + " ");
            root.launcher.setSearchText(originalText);
        }

        property Process process: Process {
            running: false

            command: [
                root.sanitizedPythonPath(),
                root.scriptPath,
                "--query",
                internal.pendingQuery,
                "--sources",
                String(root.maxSources),
                "--model",
                root.ollamaModel,
                "--output-file",
                root.outputFile.trim()
            ]

            stdout: SplitParser {
                onRead: data => {
                    internal.collectedOutput += data;
                }
            }

            stderr: SplitParser {
                onRead: data => {
                    internal.collectedError += data;
                }
            }

            onExited: function(exitCode, exitStatus) {
                root.isLoading = false;
                timeoutTimer.stop();

                if (internal.timedOut) {
                    internal.timedOut = false;
                    internal.collectedOutput = "";
                    internal.collectedError = "";
                    return;
                }

                if (internal.restartAfterStop) {
                    internal.restartAfterStop = false;
                    internal.collectedOutput = "";
                    internal.collectedError = "";
                    internal.startSearch(internal.nextQuery);
                    internal.nextQuery = "";
                    return;
                }

                const output = internal.collectedOutput.trim();
                const errorOutput = internal.collectedError.trim();
                if (exitCode !== 0 || output.length === 0) {
                    if (errorOutput.length > 0) {
                        root.errorMessage = errorOutput;
                    } else {
                        root.errorMessage = output.length > 0 ? output : "Summary failed.";
                    }
                    root.lastSummary = "";
                    root.lastTimings = "";
                } else if (output.startsWith("ERROR:")) {
                    root.errorMessage = output;
                    root.lastSummary = "";
                    root.lastTimings = "";
                } else {
                    var parsed = null;
                    if (output.startsWith("{")) {
                        try {
                            parsed = JSON.parse(output);
                        } catch (err) {
                            parsed = null;
                        }
                    }
                    if (parsed && parsed.summary) {
                        root.errorMessage = "";
                        root.lastSummary = parsed.summary;
                        root.lastTimings = formatTimings(parsed.timings_ms);
                    } else {
                        root.errorMessage = "";
                        root.lastSummary = output;
                        root.lastTimings = "";
                    }
                }

                root.lastQuery = internal.pendingQuery;
                internal.collectedOutput = "";
                internal.collectedError = "";
                internal.nextQuery = "";

                if (root.launcher) {
                    internal.refreshLauncher(root.lastQuery);
                }
            }
        }
    }

    Timer {
        id: timeoutTimer
        interval: root.maxRuntimeMs
        repeat: false

        onTriggered: {
            if (internal.process.running && internal.requestId === internal.timeoutRequestId) {
                internal.timedOut = true;
                internal.process.running = false;
                root.isLoading = false;
                root.lastSummary = "";
                root.errorMessage = "Summary timed out. Try a shorter query or fewer sources.";
                root.lastQuery = internal.pendingQuery;
                internal.refreshLauncher(root.lastQuery);
            }
        }
    }

    function getResults(searchText) {
        if (!searchText.startsWith(commandPrefix)) {
            return [];
        }

        const query = searchText.slice(commandPrefix.length).trim();

        if (query.length === 0) {
            return [];
        }

        if (query.length < minQueryLength) {
            return [
                {
                    "name": "Type more to search",
                    "description": `Enter at least ${minQueryLength} characters`,
                    "icon": "info-circle",
                    "isTablerIcon": true,
                    "isImage": false
                }
            ];
        }

        if (root.isLoading && query === internal.pendingQuery) {
            return [
                {
                    "name": "Summarizing...",
                    "description": query,
                    "icon": "loader",
                    "isTablerIcon": true,
                    "isImage": false
                }
            ];
        }

        if (root.errorMessage && query === root.lastQuery) {
            return [
                {
                    "name": "Summary failed",
                    "description": root.errorMessage,
                    "icon": "alert-circle",
                    "isTablerIcon": true,
                    "isImage": false,
                    "onActivate": function () {
                        internal.startSearch(query);
                    }
                }
            ];
        }

        if (root.lastQuery === query && root.lastSummary.length > 0) {
            var items = [
                {
                    "name": "Summary (local LLM)",
                    "description": clampSummary(root.lastSummary),
                    "icon": "sparkles",
                    "isTablerIcon": true,
                    "isImage": false,
                    "onActivate": function () {
                        openUrl(browserSearchUrl(query));
                    }
                }
            ];
            if (root.lastTimings && root.lastTimings.length > 0) {
                items.push({
                    "name": "Timings",
                    "description": root.lastTimings,
                    "icon": "timer",
                    "isTablerIcon": true,
                    "isImage": false
                });
            }
            return items;
        }

        return [
            {
                "name": "Press Enter to summarize",
                "description": `Summarize top ${root.maxSources} results`,
                "icon": "search",
                "isTablerIcon": true,
                "isImage": false,
                "onActivate": function () {
                    internal.startSearch(query);
                }
            }
        ];
    }
}
