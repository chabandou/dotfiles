import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null
    property string editPrefix: pluginApi ? (pluginApi.pluginSettings.commandPrefix ?? ">web") : ">web"
    property int editMinQueryLength: pluginApi ? (pluginApi.pluginSettings.minQueryLength ?? 3) : 3
    property int editMaxSources: pluginApi ? (pluginApi.pluginSettings.maxSources ?? 3) : 3
    property string editModel: pluginApi ? (pluginApi.pluginSettings.ollamaModel ?? "qwen2.5:1.5b-instruct") : "qwen2.5:1.5b-instruct"
    property string editPythonPath: pluginApi ? (pluginApi.pluginSettings.pythonPath ?? "python3") : "python3"
    property string editOutputFile: pluginApi ? (pluginApi.pluginSettings.outputFile ?? "~/.cache/noctalia/web-search-last.json") : "~/.cache/noctalia/web-search-last.json"

    spacing: Style.marginM

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NTextInput {
            Layout.fillWidth: true
            label: "Command Prefix"
            text: root.editPrefix
            onTextChanged: root.editPrefix = text
        }

        NLabel {
            label: "Minimum Query Length"
            description: "Minimum characters required before summarizing"
        }

        NSlider {
            from: 2
            to: 10
            value: root.editMinQueryLength
            stepSize: 1
            onValueChanged: root.editMinQueryLength = Math.round(value)
        }

        Text {
            text: `${root.editMinQueryLength} characters`
            color: Color.mOnSurfaceVariant
            font.pointSize: Style.fontSizeS
        }

        NLabel {
            label: "Sources"
            description: "How many top results to summarize"
        }

        NSlider {
            from: 1
            to: 5
            value: root.editMaxSources
            stepSize: 1
            onValueChanged: root.editMaxSources = Math.round(value)
        }

        Text {
            text: `${root.editMaxSources} sources`
            color: Color.mOnSurfaceVariant
            font.pointSize: Style.fontSizeS
        }

        NTextInput {
            Layout.fillWidth: true
            label: "Ollama Model"
            text: root.editModel
            onTextChanged: root.editModel = text
        }

        NTextInput {
            Layout.fillWidth: true
            label: "Python Path"
            text: root.editPythonPath
            onTextChanged: root.editPythonPath = text
        }

        NTextInput {
            Layout.fillWidth: true
            label: "Output File"
            text: root.editOutputFile
            onTextChanged: root.editOutputFile = text
        }

        Text {
            text: "Requires Ollama running on localhost:11434. Uses DuckDuckGo Lite directly, extracts content locally with trafilatura, and summarizes with a local model when you press Enter."
            color: Color.mOnSurfaceVariant
            font.pointSize: Style.fontSizeS
            wrapMode: Text.Wrap
        }

        Text {
            text: "If you see 'trafilatura missing', set Python Path to the interpreter where you installed it."
            color: Color.mOnSurfaceVariant
            font.pointSize: Style.fontSizeS
            wrapMode: Text.Wrap
        }

        Text {
            text: "If the summary fails with 'model not found', run `ollama pull <model>` or set a model that appears in `ollama list`."
            color: Color.mOnSurfaceVariant
            font.pointSize: Style.fontSizeS
            wrapMode: Text.Wrap
        }

        Text {
            text: "Results are saved as JSON to the output file after each run."
            color: Color.mOnSurfaceVariant
            font.pointSize: Style.fontSizeS
            wrapMode: Text.Wrap
        }
    }

    function saveSettings() {
        if (!pluginApi) {
            Logger.e("Web Search", "Cannot save settings: pluginApi is null");
            return;
        }

        const trimmedPrefix = root.editPrefix.trim();
        pluginApi.pluginSettings.commandPrefix = trimmedPrefix.length > 0 ? trimmedPrefix : ">web";
        pluginApi.pluginSettings.minQueryLength = root.editMinQueryLength;
        pluginApi.pluginSettings.maxSources = root.editMaxSources;
        pluginApi.pluginSettings.ollamaModel = root.editModel.trim().length > 0 ? root.editModel.trim() : "qwen2.5:1.5b-instruct";
        pluginApi.pluginSettings.pythonPath = root.editPythonPath.trim().length > 0 ? root.editPythonPath.trim() : "python3";
        pluginApi.pluginSettings.outputFile = root.editOutputFile.trim().length > 0 ? root.editOutputFile.trim() : "~/.cache/noctalia/web-search-last.json";
        pluginApi.saveSettings();

        Logger.i("Web Search", "Settings saved successfully");
    }
}
