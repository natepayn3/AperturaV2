pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: configEngine

    property string position: "left"
    property bool floating: true
    property int animationsDuration: 300

    readonly property bool isVertical: position === "left" || position === "right"
    readonly property string configFilePath: Quickshell.env("HOME") + "/.config/quickshell/Test/shell_settings.json"

    function loadSettings() {
        if (readProcess.output.trim() === "") {
            applyDefaults();
            return;
        }
        try {
            let parsed = JSON.parse(readProcess.output);
            if (parsed.position !== undefined) position = parsed.position;
            if (parsed.floating !== undefined) floating = parsed.floating;
            if (parsed.animationsDuration !== undefined) animationsDuration = parsed.animationsDuration;
        } catch (e) {
            applyDefaults();
        }
    }

    function saveSetting(key, value) {
        configEngine[key] = value;
        let updatePayload = {
            "position": configEngine.position,
            "floating": configEngine.floating,
            "animationsDuration": configEngine.animationsDuration
        };
        writeProcess.command = ["bash", "-c", "mkdir -p " + Quickshell.env("HOME") + "/.config/quickshell/Test && echo '" + JSON.stringify(updatePayload) + "' > " + configFilePath];
        writeProcess.running = true;
    }

    function applyDefaults() {
        position = "left";
        floating = true;
        animationsDuration = 300;
    }

    property Process initProcess: Process {
        command: ["bash", "-c", "mkdir -p " + Quickshell.env("HOME") + "/.config/quickshell/Test && [ ! -f " + configEngine.configFilePath + " ] && echo '{\"position\":\"left\",\"floating\":true,\"animationsDuration\":300}' > " + configEngine.configFilePath + " || true"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                readProcess.running = true;
            }
        }
    }

    property Process readProcess: Process {
        command: ["cat", configEngine.configFilePath]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                readProcess.output = text;
                configEngine.loadSettings();
            }
        }
        property string output: ""
    }

    property Process writeProcess: Process {
        running: false
    }
}
