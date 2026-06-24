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

    property var matugenPreviews: ({})
    property int matugenPreviewTick: 0

    readonly property var targetSchemes: [
        "scheme-tonal-spot", 
        "scheme-expressive", 
        "scheme-fruit-salad", 
        "scheme-rainbow", 
        "scheme-neutral", 
        "scheme-monochrome"
    ]
    property int currentSchemeIndex: 0
    property string activeWallpaperPath: ""
    property var temporaryPreviews: ({})

    Process {
        id: jsonReader
        command: ["cat", provider.matugenFilePath]
        stdout: StdioCollector {
            onStreamFinished: { provider.parseMatugen(this.text); }
        }
    }

    Process {
        id: variantGenerator
        running: false
        stdout: StdioCollector {
            onStreamFinished: { provider.processSingleVariant(this.text); }
        }
    }

    function reloadColors() {
        jsonReader.running = false;
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
                
                let imgPath = data.image ? data.image : "";
                if (imgPath !== "") {
                    // Sanity check: If path is relative to home directory, prepend $HOME
                    if (!imgPath.startsWith("/") && !imgPath.startsWith("file://")) {
                        let home = Quickshell.env("HOME");
                        imgPath = home + "/" + imgPath;
                    }
                    
                    provider.activeWallpaperPath = imgPath;
                    provider.currentSchemeIndex = 0;
                    provider.temporaryPreviews = {};
                    provider.kickoffNextVariant();
                }
            }
        } catch(e) { 
            console.warn("Matugen main parse error: " + e);
        }
    }

    function kickoffNextVariant() {
        if (currentSchemeIndex >= targetSchemes.length) {
            // Commit results to the interface bindings
            provider.matugenPreviews = provider.temporaryPreviews;
            provider.matugenPreviewTick++;
            return;
        }

        let currentScheme = targetSchemes[currentSchemeIndex];
        variantGenerator.command = [
            "matugen", 
            "image", provider.activeWallpaperPath, 
            "-t", currentScheme, 
            "--prefer=saturation", 
            "--json", "hex"
        ];
        variantGenerator.running = false;
        variantGenerator.running = true;
    }

    function processSingleVariant(stdoutLines) {
        // Guard against execution stalls: Always step forward even on command failures
        if (!stdoutLines || stdoutLines.trim() === "") {
            console.warn("Matugen variant returned empty output for scheme index:", currentSchemeIndex);
            provider.currentSchemeIndex++;
            provider.kickoffNextVariant();
            return;
        }

        try {
            let data = JSON.parse(stdoutLines);
            if (data && data.colors) {
                let currentScheme = targetSchemes[currentSchemeIndex];
                
                // Flexible structure evaluation to prevent parser breakage
                let primaryHex = "#ffffff";
                let outlineHex = "#ffffff";
                let bgHex = "#000000";

                if (data.colors.primary) {
                    primaryHex = data.colors.primary.dark ? data.colors.primary.dark.color : (data.colors.primary.color || data.colors.primary);
                }
                if (data.colors.outline) {
                    outlineHex = data.colors.outline.dark ? data.colors.outline.dark.color : (data.colors.outline.color || data.colors.outline);
                }
                if (data.colors.background) {
                    bgHex = data.colors.background.dark ? data.colors.background.dark.color : (data.colors.background.color || data.colors.background);
                }

                provider.temporaryPreviews[currentScheme] = [
                    Qt.color(primaryHex), 
                    Qt.color(outlineHex), 
                    Qt.color(bgHex)
                ];
            }
        } catch(e) {
            console.warn("Failed parsing scheme variant output JSON: " + e);
        }

        provider.currentSchemeIndex++;
        provider.kickoffNextVariant();
    }
}
