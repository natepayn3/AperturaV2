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
    
    // Internal state tracking to differentiate boot vs live changes
    property bool isInitialBoot: true

    Process {
        id: variantGenerator
        running: false
        stdout: StdioCollector {
            onStreamFinished: { provider.processSingleVariant(this.text); }
        }
    }

    Process {
        id: jsonReader
        command: ["cat", provider.matugenFilePath]
        stdout: StdioCollector {
            onStreamFinished: { provider.parseMatugen(this.text); }
        }
    }

    Timer {
        id: debounceTrigger
        interval: 50
        running: false
        repeat: false
        onTriggered: {
            provider.executeRecalculationLoop();
        }
    }

    onActiveWallpaperPathChanged: {
        forcePreviewRecalculation();
    }

    function forcePreviewRecalculation() {
        if (provider.activeWallpaperPath && provider.activeWallpaperPath.trim() !== "") {
            variantGenerator.running = false;
            
            if (provider.isInitialBoot) {
                // Run instantly on boot to bypass event loop scheduling latency
                provider.isInitialBoot = false;
                provider.executeRecalculationLoop();
            } else {
                // Use the safety buffer for live transitions
                debounceTrigger.stop();
                debounceTrigger.start();
            }
        }
    }

    function executeRecalculationLoop() {
        provider.currentSchemeIndex = 0;
        provider.temporaryPreviews = {};
        provider.kickoffNextVariant();
    }

    function reloadColors() {
        jsonReader.running = false;
        jsonReader.running = true;
    }

    Component.onCompleted: {
        reloadColors();
    }

    function sanitizePath(rawPath) {
        if (!rawPath || rawPath.trim() === "") return "";
        let imgPath = rawPath;
        let home = Quickshell.env("HOME");
        
        if (imgPath.startsWith("file://")) {
            imgPath = imgPath.replace("file://", "");
        }
        if (imgPath.startsWith("~/")) {
            imgPath = home + imgPath.substring(1);
        }
        if (!imgPath.startsWith("/")) {
            imgPath = home + "/" + imgPath;
        }
        return imgPath;
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
                
                if ((!provider.activeWallpaperPath || provider.activeWallpaperPath.trim() === "") && data.image) {
                    let parsedPath = provider.sanitizePath(data.image);
                    if (parsedPath !== "") {
                        provider.activeWallpaperPath = parsedPath;
                    }
                }
            }
        } catch(e) { 
            console.warn("Matugen main parse error: " + e);
        }
    }

    function kickoffNextVariant() {
        if (currentSchemeIndex >= targetSchemes.length) {
            provider.matugenPreviews = provider.temporaryPreviews;
            provider.matugenPreviewTick++;
            return;
        }

        let currentScheme = targetSchemes[currentSchemeIndex];
        let targetPath = provider.sanitizePath(provider.activeWallpaperPath);

        if (!targetPath || targetPath.trim() === "") {
            provider.currentSchemeIndex++;
            provider.kickoffNextVariant();
            return;
        }
        
        variantGenerator.command = [
            "/usr/bin/env", 
            "matugen", 
            "image", targetPath, 
            "-t", currentScheme, 
            "--prefer=saturation", 
            "--json", "hex"
        ];
        variantGenerator.running = false;
        variantGenerator.running = true;
    }

    function processSingleVariant(stdoutLines) {
        if (!stdoutLines || stdoutLines.trim() === "") {
            provider.currentSchemeIndex++;
            provider.kickoffNextVariant();
            return;
        }

        try {
            let data = JSON.parse(stdoutLines);
            if (data && data.colors) {
                let currentScheme = targetSchemes[currentSchemeIndex];
                
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
