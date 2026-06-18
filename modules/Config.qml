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
    
    // Dynamically resolve the directory this file is running from
    readonly property string basePath: Qt.resolvedUrl(".").replace("file://", "").trim()
    readonly property string configFilePath: basePath + "shell_settings.json"

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
        
        // Write directly to the dynamic path; parent directory is guaranteed to exist
        writeProcess.command = ["bash", "-c", "echo '" + JSON.stringify(updatePayload) + "' > " + configFilePath];
        writeProcess.running = true;
    }

    function applyDefaults() {
        position = "left";
        floating = true;
        animationsDuration = 300;
    }

    property Process initProcess: Process {
        // Check for file existence in the dynamic path and generate defaults if missing
        command: ["bash", "-c", "[ ! -f " + configEngine.configFilePath + " ] && echo '{\"position\":\"left\",\"floating\":true,\"animationsDuration\":300}' > " + configEngine.configFilePath + " || true"]
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
