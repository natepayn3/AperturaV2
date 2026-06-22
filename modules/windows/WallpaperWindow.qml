import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import QtQuick.Shapes
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: wallpaperWindow

    property bool active: false
    required property var rootShell

    property string currentWallpaperPath: rootShell && rootShell.wallpaperRef ? rootShell.wallpaperRef.currentWallpaperPath : ""
    property string currentScheme: "scheme-tonal-spot"

    signal applyFinished()

    Timer {
        id: startupDelayTimer
        interval: 500
        running: false
        repeat: false
        onTriggered: {
            if (currentWallpaperPath && currentWallpaperPath !== "") {
                cacheCheckProc.running = true;
            }
        }
    }

    Process {
        id: cacheCheckProc
        running: false
        command: ["fish", "-c", "test -f '" + Quickshell.env("HOME") + "/.cache/matugen-previews.json'"]
        
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                wallpaperBackend.triggerBackendRun(currentWallpaperPath, false);
            }
        }
    }

    Component.onCompleted: {
        startupDelayTimer.start();
    }

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

        onExited: {
            wallpaperWindow.applyFinished();
        }

        function triggerBackendRun(filePath, activeOnly) {
            if (!filePath || filePath === "") {
                filePath = carousel.currentFilePath || "";
                if (filePath === "") return;
            }

            let ext = filePath.split('.').pop().toLowerCase();
            let waylandDisplay = Quickshell.env("WAYLAND_DISPLAY") || "wayland-1";
            let sockPath = "/run/user/(id -u)/" + waylandDisplay + "-awww-daemon.sock";
            let script = "killall -q mpvpaper; ";
            script += "set TARGET_MON (hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'); ";
            if (activeOnly) {
                if (ext === "mp4" || ext === "webm") {
                    script += "awww clear -o \"$TARGET_MON\" 2>/dev/null; pkill -f \"mpvpaper.*$TARGET_MON\"; mpvpaper -vs -o 'loop no-audio' \"$TARGET_MON\" '" + filePath + "'; ";
                } else {
                    script += "if not pgrep -x 'awww-daemon' > /dev/null; rm -f " + sockPath + "; nohup awww-daemon >/dev/null 2>&1 & disown; sleep 0.5; end; ";
                    script += "awww img -o \"$TARGET_MON\" '" + filePath + "' --transition-type wipe --transition-step 16 --transition-duration 1; ";
                }
            } else {
                if (ext === "mp4" || ext === "webm") {
                    script += "awww kill 2>/dev/null; killall -9 -q awww-daemon; rm -f " + sockPath + "; mpvpaper -vs -o 'loop no-audio' '*' '" + filePath + "'; ";
                } else {
                    script += "if not pgrep -x 'awww-daemon' > /dev/null; rm -f " + sockPath + "; nohup awww-daemon >/dev/null 2>&1 & disown; sleep 0.5; end; ";
                    script += "awww img '" + filePath + "' --transition-type wipe --transition-step 16 --transition-duration 1; ";
                }
            }

            let matugenTarget = (ext === "mp4" || ext === "webm") 
                ? (Quickshell.env("HOME") + "/.cache/quickshell_thumbs/" + filePath.split('/').pop() + ".jpg") 
                : filePath;
            let outPath = rootShell.matugenFilePath;
            
            script += "mkdir -p (dirname '" + outPath + "'); ";
            script += "matugen image '" + matugenTarget + "' -t " + wallpaperWindow.currentScheme + " --prefer=saturation --json hex > '" + outPath + ".tmp'; ";
            script += "mv '" + outPath + ".tmp' '" + outPath + "'; sync;";

            command = ["fish", "-c", script];
            running = false;
            running = true;
        }
    }

    Process {
        id: previewBackend
        running: false
        property string lastTarget: ""
        
        onExited: {
            wallpaperWindow.applyFinished();
        }
        
        function triggerPreviewRun() {
            if (lastTarget === "") return;
            let flatPath = Quickshell.env("HOME") + "/.cache/matugen-flat.txt";
            
            let script = "rm -f " + flatPath + ".tmp; " +
                "for s in tonal-spot expressive fruit-salad rainbow neutral monochrome; " +
                "  set res (matugen image '" + lastTarget + "' -t $s --json hex); " +
                "  set p (echo $res | jq -r '.colors.primary'); " +
                "  set o (echo $res | jq -r '.colors.outline'); " +
                "  set b (echo $res | jq -r '.colors.background'); " +
                "  echo \"scheme-$s $p $o $b\" >> " + flatPath + ".tmp; " +
                "end; mv " + flatPath + ".tmp " + flatPath + "; sync;";
            command = ["fish", "-c", script];
            running = false;
            running = true;
        }
    }

    function apply(filePath, activeOnly = false, customScheme = "") {
        if (filePath && filePath !== "") currentWallpaperPath = filePath;
        if (customScheme !== "") currentScheme = customScheme;
        
        if (!currentWallpaperPath || currentWallpaperPath === "") {
            currentWallpaperPath = carousel.currentFilePath;
        }

        wallpaperBackend.triggerBackendRun(currentWallpaperPath, activeOnly);
    }

    Item {
        id: carouselContainer
        width: parent.width
        height: 600
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - ((rootShell.barPosition === "bottom") ? 46 : 10)

        PathView {
            id: carousel
            anchors.centerIn: parent
            width: parent.width - 200
            height: parent.height
            clip: false

            model: wallpaperModel
            focus: true
            interactive: true

            property int modelCount: wallpaperModel.count
            property real baseItemWidth: 270
            property real itemGap: -120
            property real cardSkew: 130
            property real radiusVal: 16
            property real expandedWidth: 924
            property real itemSpacing: baseItemWidth + itemGap
            property int maxVisible: 12
            property int dynamicItemCount: Math.min(Math.max(1, modelCount), maxVisible)
            
            pathItemCount: dynamicItemCount
            property real currentPathLength: dynamicItemCount * itemSpacing

            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: 250

            path: Path {
                startX: carousel.width / 2 - carousel.currentPathLength / 2
                startY: carousel.height / 2
                PathLine { x: carousel.width / 2 + carousel.currentPathLength / 2; y: carousel.height / 2 }
            }

            property string currentFilePath: ""
            Keys.onReturnPressed: (event) => wallpaperWindow.apply(currentFilePath, event.modifiers & Qt.ControlModifier)
            Keys.onSpacePressed: (event) => wallpaperWindow.apply(currentFilePath, event.modifiers & Qt.ControlModifier)
            Keys.onEscapePressed: wallpaperWindow.active = false

            property bool isKeyboarding: false
            property real lastMouseX: 0
            property real lastMouseY: 0
            property int hoveredIndex: -1
            property int activeIndex: (!isKeyboarding && hoveredIndex !== -1) ? hoveredIndex : currentIndex

            HoverHandler {
                onPointChanged: {
                    let dx = Math.abs(point.position.x - carousel.lastMouseX);
                    let dy = Math.abs(point.position.y - carousel.lastMouseY);
                    if (dx > 2 || dy > 2) carousel.isKeyboarding = false;
                    carousel.lastMouseX = point.position.x;
                    carousel.lastMouseY = point.position.y;
                }
            }

            Keys.onLeftPressed: { carousel.isKeyboarding = true; carousel.hoveredIndex = -1; carousel.decrementCurrentIndex(); }
            Keys.onRightPressed: { carousel.isKeyboarding = true; carousel.hoveredIndex = -1; carousel.incrementCurrentIndex(); }

            delegate: Item {
                id: delegateRoot
                width: isActiveTarget ? carousel.expandedWidth : carousel.baseItemWidth
                height: carousel.height * 0.8
                
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                
                property bool isFocused: PathView.isCurrentItem
                property bool isActiveTarget: carousel.activeIndex === index

                onIsFocusedChanged: if (isFocused) carousel.currentFilePath = filePath;
                Component.onCompleted: if (isFocused) carousel.currentFilePath = filePath;
                
                property real diff: {
                    if (carousel.modelCount === 0) return 0;
                    let d = (index - carousel.activeIndex) % carousel.modelCount;
                    if (d > carousel.modelCount / 2) d -= carousel.modelCount;
                    else if (d < -carousel.modelCount / 2) d += carousel.modelCount;
                    return d;
                }

                z: isActiveTarget ? 1000 : 500 - Math.abs(diff)

                property real pushAmount: (carousel.expandedWidth - carousel.baseItemWidth) / 2
                property real targetXShift: {
                    if (isActiveTarget || carousel.activeIndex === -1) return 0;
                    if (Math.abs(diff) > carousel.maxVisible / 2) return 0;
                    return diff < 0 ? -pushAmount : pushAmount;
                }

                Behavior on targetXShift { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                transform: Translate {
                    x: delegateRoot.targetXShift
                }

                property string pathStr: String(filePath).toLowerCase()
                property bool isVideo: pathStr.endsWith(".mp4") || pathStr.endsWith(".webm")
                property string fileName: String(filePath).split('/').pop()
                property string thumbDir: Quickshell.env("HOME") + "/.cache/quickshell_thumbs"
                property string thumbFile: thumbDir + "/" + fileName + ".jpg"
                property string thumbUrl: "file://" + thumbFile
                property bool thumbReady: false
                
                Process {
                    running: delegateRoot.isVideo && delegateRoot.isActiveTarget
                    command: ["fish", "-c", "mkdir -p '" + thumbDir + "'; if not test -f '" + thumbFile + "'; ffmpeg -y -i '" + filePath + "' -ss 00:00:00.100 -vframes 1 -vf 'scale=450:-1' -q:v 2 '" + thumbFile + "' >/dev/null 2>&1; end"]
                    onExited: delegateRoot.thumbReady = true
                }

                Item {
                    id: visualContainer
                    anchors.fill: parent
                    
                    scale: delegateRoot.isActiveTarget ? 1.0 : 0.9
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: maskLoader.item
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 0.5
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: carousel.isKeyboarding ? Qt.BlankCursor : Qt.PointingHandCursor
                        onEntered: if (!carousel.isKeyboarding) carousel.hoveredIndex = index;
                        onExited: if (carousel.hoveredIndex === index) carousel.hoveredIndex = -1;
                        onClicked: (mouse) => {
                            wallpaperWindow.apply(filePath, mouse.modifiers & Qt.ControlModifier);
                            mouse.accepted = true;
                        }
                    }
                    
                    Component {
                        id: skewShapeComp
                        Shape {
                            id: slantyShape
                            anchors.fill: parent
                            antialiasing: true
                            preferredRendererType: Shape.CurveRenderer
                            
                            property real r: carousel.radiusVal
                            property real sk: carousel.cardSkew
                            
                            ShapePath {
                                id: sPath
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

                    Loader {
                        id: maskLoader
                        active: true
                        sourceComponent: Shape {
                            width: visualContainer.width; height: visualContainer.height
                            layer.enabled: true
                            ShapePath {
                                fillColor: "white"; strokeColor: "transparent"
                                startX: carousel.cardSkew + carousel.radiusVal; startY: 0
                                PathLine { x: visualContainer.width - carousel.radiusVal; y: 0 }
                                PathQuad { x: visualContainer.width - (carousel.radiusVal * 0.2); y: carousel.radiusVal; controlX: visualContainer.width; controlY: 0 }
                                PathLine { x: visualContainer.width - carousel.cardSkew + (carousel.radiusVal * 0.2); y: visualContainer.height - carousel.radiusVal }
                                PathQuad { x: visualContainer.width - carousel.cardSkew - carousel.radiusVal; y: visualContainer.height; controlX: visualContainer.width - carousel.cardSkew; controlY: visualContainer.height }
                                PathLine { x: carousel.radiusVal; y: visualContainer.height }
                                PathQuad { x: (carousel.radiusVal * 0.2); y: visualContainer.height - carousel.radiusVal; controlX: 0; controlY: visualContainer.height }
                                PathLine { x: carousel.cardSkew - (carousel.radiusVal * 0.2); y: carousel.radiusVal }
                                PathQuad { x: carousel.cardSkew + carousel.radiusVal; y: 0; controlX: carousel.cardSkew; controlY: 0 }
                            }
                        }
                    }

                    Image {
                        id: bgImg
                        anchors.fill: parent
                        source: delegateRoot.isVideo ? (delegateRoot.thumbReady ? delegateRoot.thumbUrl : "") : fileUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(900, 520)
                        cache: true
                        visible: false
                    }

                    Loader {
                        id: vidLoader
                        anchors.fill: parent
                        active: delegateRoot.isVideo && delegateRoot.isActiveTarget
                        visible: false
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

                    MultiEffect {
                        anchors.fill: parent
                        source: vidLoader.active ? vidLoader.item : bgImg
                        maskEnabled: true
                        maskSource: maskLoader.item
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 0.5
                    }

                    Loader {
                        anchors.fill: parent
                        active: delegateRoot.isActiveTarget
                        z: 5
                        sourceComponent: Component {
                            Item {
                                anchors.fill: parent
                                Shape {
                                    id: glowOutline
                                    anchors.fill: parent
                                    antialiasing: true
                                    
                                    property real r: carousel.radiusVal
                                    property real sk: carousel.cardSkew
                                    
                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: rootShell.primaryColor ? Qt.color(rootShell.primaryColor) : "#ffffff"
                                        strokeWidth: 3
                                        
                                        startX: glowOutline.sk + glowOutline.r; startY: 0
                                        PathLine { x: glowOutline.width - glowOutline.r; y: 0 }
                                        PathQuad { x: glowOutline.width - (glowOutline.r * 0.2); y: glowOutline.r; controlX: glowOutline.width; controlY: 0 }
                                        PathLine { x: glowOutline.width - glowOutline.sk + (glowOutline.r * 0.2); y: glowOutline.height - glowOutline.r }
                                        PathQuad { x: glowOutline.width - glowOutline.sk - glowOutline.r; y: glowOutline.height; controlX: glowOutline.width - glowOutline.sk; controlY: glowOutline.height }
                                        PathLine { x: glowOutline.r; y: glowOutline.height }
                                        PathQuad { x: (glowOutline.r * 0.2); y: glowOutline.height - glowOutline.r; controlX: 0; controlY: glowOutline.height }
                                        PathLine { x: glowOutline.sk - (glowOutline.r * 0.2); y: glowOutline.r }
                                        PathQuad { x: glowOutline.sk + glowOutline.r; y: 0; controlX: glowOutline.sk; controlY: 0 }
                                    }
                                }
                                MultiEffect {
                                    anchors.fill: parent
                                    source: glowOutline
                                    shadowEnabled: true
                                    shadowColor: rootShell.primaryColor ? Qt.color(rootShell.primaryColor) : "#ffffff"
                                    shadowBlur: 0.8
                                    shadowVerticalOffset: 0
                                    shadowHorizontalOffset: 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
