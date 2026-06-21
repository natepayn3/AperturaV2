import QtQuick
import Quickshell
import Quickshell.Io
import ".." // Import parent dir to access Config.qml singleton

Item {
    id: provider

    readonly property string matugenFilePath: Quickshell.env("HOME") + "/.config/quickshell/AperturaV2/matugen.json"

    // 🔒 Internal properties to hold the raw parsed Matugen data
    property color _matBackground: "#cc11111b"
    property color _matBorder: "#313244"
    property color _matAccent: "#89b4fa"

    // 🔀 The exposed properties dynamically switch based on the Config state
    property color background: Config.shutterMode ? "#0B0F19" : _matBackground // Solid obsidian, no alpha
    property color border: Config.shutterMode ? "#1A1A1A" : _matBorder
    property color accent: Config.shutterMode ? "#FFFFFF" : _matAccent
    
    // Move text colors here to make this the true single source of truth
    property color textPrimary: Config.shutterMode ? "#FFFFFF" : "#cdd6f4"
    property color textSub: Config.shutterMode ? "#A0A0A0" : "#a6adc8"

    function parseMatugen(jsonString) {
        if (!jsonString || jsonString.trim() === "") return;
        try {
            let data = JSON.parse(jsonString);
            if (data && data.colors) {
                let c = data.colors;
                let rawBg = c.background && c.background.dark ? c.background.dark.color.replace("#", "") : "11111b";
                let rawBorder = c.outline && c.outline.dark ? c.outline.dark.color.replace("#", "") : "313244";
                let rawAccent = c.primary && c.primary.dark ? c.primary.dark.color.replace("#", "") : "89b4fa";
                
                // Write to the internal properties, NOT the exposed ones
                _matBackground = Qt.color("#cc" + rawBg);
                _matBorder     = Qt.color("#" + rawBorder);
                _matAccent     = Qt.color("#" + rawAccent);
            }
        } catch(e) {
            console.warn("MatugenProvider failed to parse JSON: " + e);
        }
    }

    // 🎯 Native Quickshell file tracking and loading engine combined
    FileView {
        id: matugenFile
        path: provider.matugenFilePath
        watchChanges: true // Automatically triggers onFileChanged when wallpaper window updates it

        // Parse initial text immediately on boot
        onLoaded: provider.parseMatugen(matugenFile.text())
        
        // Live update whenever the file content updates on disk
        onFileChanged: {
            matugenFile.reload();
            provider.parseMatugen(matugenFile.text());
        }
    }
}
