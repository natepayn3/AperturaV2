import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../"

PanelWindow {
    id: wallpaperWindow

    Component.onCompleted: {
        // 🎯 Initialize the target file on boot so Matugen has a target before the first click
        // Replace 'rootShell.startupWallpaperPath' with wherever you store your boot wallpaper
        if (rootShell && rootShell.startupWallpaperPath) {
            matugenRunner.targetFile = rootShell.startupWallpaperPath;
        }
    }

    required property var rootShell
    property bool active: false

    WlrLayershell.namespace: "quickshell-wallpaper"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    exclusionMode: ExclusionMode.Ignore
    
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: contentWrapper.opacity > 0.01

    onActiveChanged: {
        if (active) carousel.forceActiveFocus();
    }

    MouseArea {
        anchors.fill: parent
        onClicked: wallpaperWindow.active = false
    }

    FolderListModel {
        id: wallpaperModel
        folder: "file://" + Quickshell.env("HOME") + "/Pictures/Wallpapers"
        nameFilters: ["*.jpg", "*.png", "*.gif", "*.mp4", "*.webm"]
        showDirs: false
    }

    // 🎯 Track the active scheme locally
    property string activeScheme: "scheme-tonal-spot"

    // 🎯 The Public Bridge: ColorsLayout will call this to force an update
    function triggerMatugen(filePath, newScheme) {
        if (filePath) matugenRunner.targetFile = filePath;
        if (newScheme) activeScheme = newScheme;
        
        // Don't run if we haven't picked a wallpaper yet
        if (matugenRunner.targetFile === "") return;

        matugenRunner.running = false;
        matugenRunner.running = true;
    }

    // 🎯 Dynamically grab the same path SettingsApp uses
    readonly property string configFilePath: rootShell ? rootShell.customBasePath + "/shell_settings.json" : ""

    // 🎯 1. Boot Sync: Pulls the last known wallpaper into memory immediately on launch
    Process {
        id: bootConfigReader
        command: ["cat", wallpaperWindow.configFilePath]
        running: true
        stdout: StdioCollector {
            onTextChanged: {
                if (text.trim() === "") return;
                try {
                    let config = JSON.parse(text);
                    if (config.current_wallpaper) {
                        matugenRunner.targetFile = config.current_wallpaper;
                    }
                    if (config.matugen_scheme) {
                        wallpaperWindow.activeScheme = config.matugen_scheme;
                    }
                } catch(e) {}
            }
        }
    }

    // 🎯 2. State Writer: Updates the JSON silently when you select a new media file
    Process {
        id: wallpaperStateWriter
        running: false
        property string newWall: ""
        command: [
            "bash", "-c", 
            "if [ ! -f '" + wallpaperWindow.configFilePath + "' ]; then echo '{}' > '" + wallpaperWindow.configFilePath + "'; fi && " +
            "jq '.current_wallpaper = \"" + newWall + "\"' '" + wallpaperWindow.configFilePath + "' > /tmp/shell_settings.tmp && mv /tmp/shell_settings.tmp '" + wallpaperWindow.configFilePath + "'"
        ]
    }

    // 🎯 1. The Trigger
    Process {
        id: wallpaperBackend
        running: false
        property string targetFile: ""

        function apply(filePath) {
            targetFile = filePath;
            let ext = filePath.split('.').pop().toLowerCase();
            
            if (ext === "mp4" || ext === "webm") {
                command = ["sh", "-c", "killall awww-daemon; mpvpaper -vs -o 'loop no-audio' '*' '" + filePath + "'"];
            } else {
                command = ["sh", "-c", "killall mpvpaper; awww-daemon & awww img '" + filePath + "' --transition-type fade --transition-step 150"];
            }
            running = true;
            
            // 🎯 Safely patch the JSON file with the new path
            wallpaperStateWriter.newWall = filePath;
            wallpaperStateWriter.running = false;
            wallpaperStateWriter.running = true;
            
            triggerMatugen(filePath, null); 
        }
    }

    // 🎯 2. The Writer
    Process {
        id: matugenRunner
        running: false
        property string targetFile: ""
        
        // 🎯 Injects the dynamic scheme variable into the bash command
        // Note: Matugen v2 uses `-t` for type/scheme. Adjust if using an older version.
        command: [
            "sh", "-c", 
            "matugen image \"" + targetFile + "\" -t " + wallpaperWindow.activeScheme + " --prefer=saturation --json hex > \"" + rootShell.matugenFilePath + "\" && sync"
        ]

        // 🎯 Removed the ghost ID reference that was crashing the QML engine.
        // FileView autonomously handles the reload via watchChanges, so we don't need onExited logic here anymore.
    }

    // 🎯 Native Quickshell file tracker - No more XHR or Process hacks
    FileView {
        id: matugenReader
        path: rootShell.matugenFilePath
        watchChanges: true
        
        // 🎯 CRITICAL: This is what tells the engine to pull the fresh bytes off the disk!
        onFileChanged: reload() 
        
        onTextChanged: {
            // Retrieve the live string text from the wrapper function
            let fileContent = matugenReader.text(); 
            
            if (fileContent && fileContent.trim() !== "") {
                rootShell.parseMatugen(fileContent);
            }
        }
    }

    Item {
        id: contentWrapper
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: 80
        height: 320 

        opacity: wallpaperWindow.active ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        transform: Translate {
            y: wallpaperWindow.active ? 0 : 40
            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        }

        // 🎯 Horizontally center the list layout relative to your monitor bounds
        Item {
            id: carouselContainer
            height: parent.height
            // 🎯 Fits perfectly on screen while adapting smoothly when elements grow/shrink
            width: Math.min(parent.width - 100, carousel.contentWidth)
            anchors.horizontalCenter: parent.horizontalCenter

            ListView {
                id: carousel
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: 4 
                model: wallpaperModel
                
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                
                focus: true 
                keyNavigationEnabled: true
                highlightMoveDuration: 200

                Keys.onEscapePressed: wallpaperWindow.active = false

                delegate: Item {
                    width: isFocused ? 200 : 140
                    height: carousel.height
                    
                    property bool isFocused: ListView.isCurrentItem
                    // 🎯 Tracks if we have paused long enough to load heavy media
                    property bool loadHeavyMedia: false 
                    z: isFocused ? 10 : 1

                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                    // 🎯 Debounce timer to prevent stuttering when skipping past items quickly
                    Timer {
                        id: mediaDebounce
                        interval: 150 
                        running: isFocused
                        onTriggered: loadHeavyMedia = true
                    }

                    // 🎯 Clean up memory immediately when focus is lost
                    onIsFocusedChanged: {
                        if (!isFocused) {
                            loadHeavyMedia = false;
                        }
                    }

                    // 🎯 Catch clicks, enable hover focus, and change cursor
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor 
                        
                        onEntered: carousel.currentIndex = index 
                        
                        onClicked: {
                            carousel.currentIndex = index;
                            wallpaperBackend.apply(filePath);
                        }
                    }

                    Keys.onReturnPressed: if (isFocused) wallpaperBackend.apply(filePath)
                    Keys.onSpacePressed: if (isFocused) wallpaperBackend.apply(filePath)

                    // 🎯 The Main Card Frame
                    Item {
                        id: slantedCard
                        anchors.centerIn: parent
                        height: parent.height * 0.9
                        width: parent.width
                        clip: true 

                        scale: isFocused ? 1.25 : 0.95
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                        // 🎯 True Geometric Shear Matrix
                        transform: Matrix4x4 {
                            matrix: Qt.matrix4x4(
                                1.0, -0.16,  0.0,  0.0,  
                                0.0,  1.0,  0.0,  0.0,
                                0.0,  0.0,  1.0,  0.0,
                                0.0,  0.0,  0.0,  1.0
                            )
                        }

                        // 🎯 The Direct Media Wrapper
                        Item {
                            anchors.centerIn: parent
                            width: parent.width * 1.5
                            height: parent.height

                            // Helper properties for clean conditional logic
                            property bool isVideo: filePath.endsWith(".mp4") || filePath.endsWith(".webm")
                            property bool isGif: filePath.endsWith(".gif")
                            property bool isStaticImage: !isVideo && !isGif

                            Image {
                                anchors.fill: parent
                                // 🎯 Only assign source if it's an actual image
                                source: isStaticImage ? fileUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true 
                                sourceSize: Qt.size(300, parent.height) 
                                cache: true
                                visible: isStaticImage
                            }

                            AnimatedImage {
                                anchors.fill: parent
                                // 🎯 Only decode if focused AND it is actually a gif
                                source: (loadHeavyMedia && isGif) ? fileUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: isGif
                            }

                            Video {
                                anchors.fill: parent
                                // 🎯 Stop the CUDA engine from trying to play JPEGs
                                source: (loadHeavyMedia && isVideo) ? fileUrl : ""
                                fillMode: VideoOutput.PreserveAspectCrop
                                loops: MediaPlayer.Infinite
                                autoPlay: true 
                                muted: true
                                visible: isVideo
                            }
                        }
                    }
                }               
            }
        }
    }
}
