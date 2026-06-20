import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: provider

    // The single source of truth for color properties
    property color background: "#11111b"
    property color border: "#313244"
    property color accent: "#89b4fa"

    readonly property string matugenFilePath: Quickshell.env("HOME") + "/.config/quickshell/AperturaV2/matugen.json"

    function parseMatugen(jsonString) {
        if (!jsonString || jsonString.trim() === "") return;
        try {
            let data = JSON.parse(jsonString);
            if (data && data.colors) {
                let c = data.colors;
                
                let rawBg = c.background && c.background.dark ? c.background.dark.color.replace("#", "") : "11111b";
                let rawBorder = c.outline && c.outline.dark ? c.outline.dark.color.replace("#", "") : "313244";
                let rawAccent = c.primary && c.primary.dark ? c.primary.dark.color.replace("#", "") : "89b4fa";
                
                background = Qt.color("#cc" + rawBg);
                border     = Qt.color("#" + rawBorder);
                accent     = Qt.color("#" + rawAccent);
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
