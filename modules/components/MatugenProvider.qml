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
            onStreamFinished: { provider.parseGeneratedVariants(this.text); }
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
                    // Added --prefer=saturation to prevent interactive stdin lockups
                    let script = "for s in scheme-tonal-spot scheme-expressive scheme-fruit-salad scheme-rainbow scheme-neutral scheme-monochrome; do " +
                                 "  res=$(matugen image '" + imgPath + "' -t $s --prefer=saturation --json hex 2>/dev/null); " +
                                 "  p=$(echo \"$res\" | jq -r '.colors.primary | if type==\"object\" then (.dark.color // empty) else . end' 2>/dev/null); " +
                                 "  o=$(echo \"$res\" | jq -r '.colors.outline | if type==\"object\" then (.dark.color // empty) else . end' 2>/dev/null); " +
                                 "  b=$(echo \"$res\" | jq -r '.colors.background | if type==\"object\" then (.dark.color // empty) else . end' 2>/dev/null); " +
                                 "  if [ -n \"$p\" ] && [ \"$p\" != \"null\" ]; then echo \"$s $p $o $b\"; fi; " +
                                 "done";
                                 
                    variantGenerator.command = ["bash", "-c", script];
                    variantGenerator.running = false;
                    variantGenerator.running = true;
                }
            }
        } catch(e) { 
            console.warn("Matugen main parse error: " + e); 
        }
    }

    function parseGeneratedVariants(stdoutLines) {
        if (!stdoutLines || stdoutLines.trim() === "") return;

        try {
            let lines = stdoutLines.split("\n");
            let updatedPreviews = {};

            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line === "") continue;

                let parts = line.split(" ");
                if (parts.length >= 4) {
                    let schemeId = parts[0];
                    let primary  = parts[1];
                    let outline  = parts[2];
                    let bg       = parts[3];
                    
                    updatedPreviews[schemeId] = [primary, outline, bg]; 
                }
            }

            if (Object.keys(updatedPreviews).length > 0) {
                provider.matugenPreviews = updatedPreviews;
                provider.matugenPreviewTick++;
            }
        } catch(e) { 
            console.warn("Variant processing failed: " + e); 
        }
    }
}
