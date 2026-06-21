import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: provider

    property bool isShutterMode: false

    readonly property string matugenFilePath: Quickshell.env("HOME") + "/.config/quickshell/AperturaV2/matugen.json"

    property color _matBackground: "#cc11111b"
    property color _matBorder: "#313244"
    property color _matAccent: "#89b4fa"

    property color background: isShutterMode ? "#0B0F19" : _matBackground
    property color border: isShutterMode ? "#1A1A1A" : _matBorder
    property color accent: isShutterMode ? "#FFFFFF" : _matAccent
    
    property color textPrimary: isShutterMode ? "#FFFFFF" : "#cdd6f4"
    property color textSub: isShutterMode ? "#A0A0A0" : "#a6adc8"

    // 🎯 Quickshell's Process requires a DataStreamParser (like StdioCollector)
    Process {
        id: jsonReader
        command: ["cat", provider.matugenFilePath]
        
        // Collects the entire stdout stream until the cat process closes
        stdout: StdioCollector {
            onStreamFinished: {
                // 'this.text' contains the full buffered string from the command
                provider.parseMatugen(this.text);
            }
        }
    }

    function reloadColors() {
        jsonReader.running = true;
    }

    Component.onCompleted: {
        reloadColors();
    }

    function parseMatugen(jsonString) {
        if (!jsonString || jsonString.trim() === "") return;
        try {
            let data = JSON.parse(jsonString);
            if (data && data.colors) {
                let c = data.colors;
                let rawBg = c.background && c.background.dark ? c.background.dark.color.replace("#", "") : "11111b";
                let rawBorder = c.outline && c.outline.dark ? c.outline.dark.color.replace("#", "") : "313244";
                let rawAccent = c.primary && c.primary.dark ? c.primary.dark.color.replace("#", "") : "89b4fa";
                
                _matBackground = Qt.color("#cc" + rawBg);
                _matBorder     = Qt.color("#" + rawBorder);
                _matAccent     = Qt.color("#" + rawAccent);
            }
        } catch(e) {
            console.warn("MatugenProvider failed to parse JSON: " + e);
        }
    }
}
