import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import QtQuick.Shapes
import QtQuick.Effects
import QtMultimedia     // 🎯 Required for the Video playback
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: wallpaperWindow

    

    property bool active: false
    required property var rootShell

    // 🎯 THE RELIABLE ROOT SCOPE PROPERTIES
    property string currentWallpaperPath: ""
    property string currentScheme: "scheme-tonal-spot"

    WlrLayershell.namespace: "quickshell-wallpaper"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    exclusionMode: ExclusionMode.Ignore
    
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: active

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

    Process {
        id: wallpaperBackend
        running: false

        // Move the core script generation inside a clean root-accessible function
        function triggerBackendRun(filePath, activeOnly) {
            let ext = filePath.split('.').pop().toLowerCase();
            let sockPath = "/run/user/$(id -u)/${WAYLAND_DISPLAY:-wayland-1}-awww-daemon.sock";
            
            let script = "killall -q mpvpaper; ";
            
            if (activeOnly) {
                script += "TARGET_MON=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'); ";
                if (ext === "mp4" || ext === "webm") {
                    script += "awww clear -o \"$TARGET_MON\" 2>/dev/null; pkill -f \"mpvpaper.*$TARGET_MON\" || true; mpvpaper -vs -o 'loop no-audio' \"$TARGET_MON\" '" + filePath + "'; ";
                } else {
                    script += "if ! pgrep -x 'awww-daemon' > /dev/null; then rm -f " + sockPath + "; nohup awww-daemon >/dev/null 2>&1 & disown; sleep 0.5; fi; ";
                    script += "awww img -o \"$TARGET_MON\" '" + filePath + "' --transition-type wipe --transition-step 16 --transition-duration 1; ";
                }
            } else {
                if (ext === "mp4" || ext === "webm") {
                    script += "awww kill 2>/dev/null || killall -9 -q awww-daemon; rm -f " + sockPath + "; mpvpaper -vs -o 'loop no-audio' '*' '" + filePath + "'; ";
                } else {
                    script += "if ! pgrep -x 'awww-daemon' > /dev/null; then rm -f " + sockPath + "; nohup awww-daemon >/dev/null 2>&1 & disown; sleep 0.5; fi; ";
                    script += "awww img '" + filePath + "' --transition-type wipe --transition-step 16 --transition-duration 1; ";
                }
            }

            let matugenTarget = (ext === "mp4" || ext === "webm") 
                ? (Quickshell.env("HOME") + "/.cache/quickshell_thumbs/" + filePath.split('/').pop() + ".jpg") 
                : filePath;

            let outPath = rootShell.matugenFilePath;
            script += "mkdir -p \"$(dirname '" + outPath + "')\" && ";
            script += "matugen image '" + matugenTarget + "' -t " + wallpaperWindow.currentScheme + " --prefer=saturation --json hex > '" + outPath + ".tmp' && ";
            script += "mv '" + outPath + ".tmp' '" + outPath + "' && sync";

            command = ["bash", "-c", script];
            running = false;
            running = true;
        }
    }

    function apply(filePath, activeOnly = false, customScheme = "") {
        if (filePath && filePath !== "") currentWallpaperPath = filePath;
        if (customScheme !== "") currentScheme = customScheme;
        
        // Fallback to carousel's active selection if an explicit file wasn't provided
        if (!currentWallpaperPath || currentWallpaperPath === "") {
            currentWallpaperPath = carousel.currentFilePath;
        }

        wallpaperBackend.triggerBackendRun(currentWallpaperPath, activeOnly);
    }

    Process {
        id: matugenRunner
        running: false
        property string targetFile: ""
        command: [
            "sh", "-c", 
            "matugen image \"" + targetFile + "\" -t scheme-tonal-spot --prefer=saturation --json hex > \"" + rootShell.matugenFilePath + "\" && sync"
        ]
    }

    Item {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: 80
        height: 450 

        // 🎯 --- NEW: HOVER SCROLL LOGIC ---
        Timer {
            id: hoverScrollTimer
            interval: 150 
            repeat: true
            property int direction: 0 // -1 for left, 1 for right

            onTriggered: {
                // If keyboard is used while hovering, yield to the keyboard and stop scrolling
                if (carousel.isKeyboarding) {
                    stop();
                    return;
                }
                
                if (direction === -1) {
                    carousel.currentIndex = Math.max(0, carousel.currentIndex - 1);
                } else if (direction === 1) {
                    carousel.currentIndex = Math.min(carousel.count - 1, carousel.currentIndex + 1);
                }
            }
        }

        // 🎯 Left Edge Trigger Zone
        Item {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 300 // Adjust this to make the trigger area wider/narrower
            z: 20 // Sits above the list visually, but HoverHandler lets clicks pass through

            HoverHandler {
                onHoveredChanged: {
                    if (hovered && !carousel.isKeyboarding) {
                        hoverScrollTimer.direction = -1;
                        hoverScrollTimer.start();
                    } else if (hoverScrollTimer.direction === -1) {
                        hoverScrollTimer.stop();
                    }
                }
            }
        }

        // 🎯 Right Edge Trigger Zone
        Item {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 300 
            z: 20

            HoverHandler {
                onHoveredChanged: {
                    if (hovered && !carousel.isKeyboarding) {
                        hoverScrollTimer.direction = 1;
                        hoverScrollTimer.start();
                    } else if (hoverScrollTimer.direction === 1) {
                        hoverScrollTimer.stop();
                    }
                }
            }
        }
        // 🎯 --- END NEW LOGIC ---

        ListView {
            id: carousel
            anchors.centerIn: parent
            width: parent.width - 400
            height: parent.height
            clip: false 
            orientation: ListView.Horizontal
            property real cardSkew: 35
            spacing: -cardSkew + 5 
            cacheBuffer: 3000

            leftMargin: width / 2 - 90
            rightMargin: width / 2 - 90

            model: wallpaperModel
            focus: true
            interactive: true 

            preferredHighlightBegin: width / 2 - 90
            preferredHighlightEnd: width / 2 + 90
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: 200

            property string currentFilePath: ""
            Keys.onReturnPressed: wallpaperWindow.apply(currentFilePath, event.modifiers & Qt.ControlModifier)
            Keys.onSpacePressed: wallpaperWindow.apply(currentFilePath, event.modifiers & Qt.ControlModifier)
            Keys.onEscapePressed: wallpaperWindow.active = false

            // 🎯 --- THE PHYSICAL MOUSE TRACKER ---
            // Replaced the timer with strict boolean and global coordinate trackers
            property bool isKeyboarding: false
            property real lastMouseX: 0
            property real lastMouseY: 0
            
            property int hoveredIndex: -1
            property int activeIndex: (!isKeyboarding && hoveredIndex !== -1) ? hoveredIndex : currentIndex

            Keys.onLeftPressed: {
                carousel.isKeyboarding = true;
                carousel.hoveredIndex = -1; 
                if (currentIndex > 0) currentIndex--;
            }
            Keys.onRightPressed: {
                carousel.isKeyboarding = true;
                carousel.hoveredIndex = -1; 
                if (currentIndex < count - 1) currentIndex++;
            }

            WheelHandler {
                onWheel: (event) => {
                    carousel.isKeyboarding = false; // Using the wheel naturally restores the mouse
                    if (event.angleDelta.y > 0 || event.angleDelta.x > 0) {
                        carousel.currentIndex = Math.max(0, carousel.currentIndex - 1);
                    } else if (event.angleDelta.y < 0 || event.angleDelta.x < 0) {
                        carousel.currentIndex = Math.min(carousel.count - 1, carousel.currentIndex + 1);
                    }
                }
            }

            property real expandedWidth: height * 0.85 * 1.77 + cardSkew
            property real extraWidth: expandedWidth - 180

            delegate: Item {
                id: delegateRoot
                width: 180 
                height: carousel.height
                
                property bool isFocused: ListView.isCurrentItem
                property bool isActiveTarget: carousel.activeIndex === index
                
                onIsFocusedChanged: if (isFocused) carousel.currentFilePath = filePath;
                Component.onCompleted: if (isFocused) carousel.currentFilePath = filePath;
                
                property real targetXShift: {
                    if (index < carousel.activeIndex) return -(carousel.extraWidth / 2);
                    if (index > carousel.activeIndex) return (carousel.extraWidth / 2);
                    return 0; 
                }

                Behavior on targetXShift { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                z: isActiveTarget ? 10 : 1 

                property string pathStr: String(filePath).toLowerCase()
                property bool isVideo: pathStr.endsWith(".mp4") || pathStr.endsWith(".webm")
                property string fileName: String(filePath).split('/').pop()
                property string thumbDir: Quickshell.env("HOME") + "/.cache/quickshell_thumbs"
                property string thumbFile: thumbDir + "/" + fileName + ".jpg"
                property string thumbUrl: "file://" + thumbFile
                property bool thumbReady: false
                
                Process {
                    running: delegateRoot.isVideo
                    command: [
                        "bash", "-c", 
                        "mkdir -p '" + thumbDir + "' && if [ ! -f '" + thumbFile + "' ]; then ffmpeg -y -i '" + filePath + "' -ss 00:00:00.100 -vframes 1 -vf 'scale=450:-1' -q:v 2 '" + thumbFile + "' >/dev/null 2>&1; fi"
                    ]
                    onExited: delegateRoot.thumbReady = true
                }

                Item {
                    id: visualContainer
                    anchors.verticalCenter: parent.verticalCenter
                    x: (delegateRoot.width - width) / 2 + delegateRoot.targetXShift
                    height: parent.height * 0.85 
                    
                    width: delegateRoot.isActiveTarget ? carousel.expandedWidth : delegateRoot.width 
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    
                    scale: delegateRoot.isActiveTarget ? 1.05 : 0.95
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                    property real relX: delegateRoot.x - carousel.contentX
                    property real visualX: relX + x
                    property bool isFullyVisible: visualX >= -5 && (visualX + width) <= (carousel.width + 5)
                    
                    opacity: isFullyVisible ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    visible: opacity > 0.01

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: carousel.isKeyboarding ? Qt.BlankCursor : Qt.PointingHandCursor 
                        
                        // 🎯 Tracks actual physical device movement instead of UI layout shifts
                        onPositionChanged: (mouse) => {
                            // Map local coordinate to the absolute global window
                            let globalPos = mapToItem(null, mouse.x, mouse.y);
                            
                            // Check if the physical mouse moved more than 2 pixels (avoids rounding errors)
                            let dx = Math.abs(globalPos.x - carousel.lastMouseX);
                            let dy = Math.abs(globalPos.y - carousel.lastMouseY);

                            if (dx > 2 || dy > 2) {
                                carousel.isKeyboarding = false; 
                            }

                            carousel.lastMouseX = globalPos.x;
                            carousel.lastMouseY = globalPos.y;

                            if (!carousel.isKeyboarding && carousel.hoveredIndex !== index) {
                                carousel.hoveredIndex = index;
                            }
                        }
                        
                        onEntered: if (!carousel.isKeyboarding) carousel.hoveredIndex = index;
                        onExited: if (carousel.hoveredIndex === index) carousel.hoveredIndex = -1;
                        
                        onClicked: (mouse) => wallpaperWindow.apply(filePath, mouse.modifiers & Qt.ControlModifier)
                    }
                    
                    Item {
                        id: cardMask
                        anchors.fill: parent
                        visible: false 
                        layer.enabled: true
                        layer.smooth: true
                        
                        Shape {
                            id: slantyShape 
                            anchors.fill: parent
                            antialiasing: true
                            preferredRendererType: Shape.CurveRenderer
                            
                            property real r: 12 
                            property real sk: carousel.cardSkew
                            
                            ShapePath {
                                fillColor: "white"
                                strokeColor: "transparent"
                                startX: slantyShape.sk + slantyShape.r; startY: 0
                                PathLine { x: slantyShape.width - slantyShape.r; y: 0 }
                                PathQuad { x: slantyShape.width - (slantyShape.r * 0.2); y: slantyShape.r; controlX: slantyShape.width; controlY: 0 }
                                PathLine { x: slantyShape.width - slantyShape.sk + (slantyShape.r * 0.2); y: slantyShape.height - slantyShape.r }
                                PathQuad { x: slantyShape.width - slantyShape.sk - slantyShape.r; y: slantyShape.height; controlX: slantyShape.width - slantyShape.sk; controlY: slantyShape.height }
                                PathLine { x: slantyShape.r; y: slantyShape.height }
                                PathQuad { x: (slantyShape.r * 0.2); y: slantyShape.height - slantyShape.r; controlX: 0; controlY: slantyShape.height }
                                PathLine { x: slantyShape.sk - (slantyShape.r * 0.2); y: slantyShape.r }
                                PathQuad { x: slantyShape.sk + slantyShape.r; y: 0; controlX: slantyShape.sk; controlY: 0 }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        
                        Image {
                            anchors.fill: parent
                            source: delegateRoot.isVideo ? (delegateRoot.thumbReady ? delegateRoot.thumbUrl : "") : fileUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true 
                            sourceSize: Qt.size(450, 450) 
                            cache: true
                        }

                        Loader {
                            anchors.fill: parent
                            active: delegateRoot.isVideo && delegateRoot.isActiveTarget
                            sourceComponent: Component {
                                Video {
                                    anchors.fill: parent
                                    source: fileUrl
                                    fillMode: VideoOutput.PreserveAspectCrop
                                    loops: MediaPlayer.Infinite
                                    muted: true
                                    Component.onCompleted: play()
                                }
                            }
                        }

                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: cardMask
                            maskThresholdMin: 0.3 
                            maskSpreadAtMin: 0.3
                        }
                    }
                }
            }
        }
    }
}
