pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: configEngine

    property string position: "left"
    property bool floating: true
    property int animationsDuration: 300
    // 🎯 Declare the missing property with a default value
    property bool shutterMode: false

    readonly property bool isVertical: position === "left" || position === "right"
    
    readonly property string basePath: Qt.resolvedUrl(".").toString().replace("file://", "").trim()
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
            // 🎯 Add it to the parser
            if (parsed.shutterMode !== undefined) shutterMode = parsed.shutterMode;
        } catch (e) {
            applyDefaults();
        }
    }

    function saveSetting(key, value) {
        configEngine[key] = value;
        let updatePayload = {
            "position": configEngine.position,
            "floating": configEngine.floating,
            "animationsDuration": configEngine.animationsDuration,
            // 🎯 Include it in the save payload
            "shutterMode": configEngine.shutterMode
        };
        
        writeProcess.command = ["bash", "-c", "echo '" + JSON.stringify(updatePayload) + "' > " + configFilePath];
        writeProcess.running = true;
    }

    function applyDefaults() {
        position = "left";
        floating = true;
        animationsDuration = 300;
        // 🎯 Add to defaults
        shutterMode = false; 
    }

    property Process initProcess: Process {
        // 🎯 Inject shutterMode into the fallback JSON generation string
        command: ["bash", "-c", "[ ! -f " + configEngine.configFilePath + " ] && echo '{\"position\":\"left\",\"floating\":true,\"animationsDuration\":300,\"shutterMode\":false}' > " + configEngine.configFilePath + " || true"]
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
