import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: radialMenuWindow
    
    // Load configuration
    Config {
        id: config
    }
    
    // Configuration from Config.qml
    property int menuRadius: config.menuRadius
    property int circleSize: config.circleSize
    property int itemCount: config.itemCount
    property int hoveredIndex: -1
    
    // Cursor position when menu was opened (screen-relative)
    property real cursorX: 0
    property real cursorY: 0
    
    // Colors from Config.qml
    property color itemColor: config.itemColor
    property color itemHoverColor: config.itemHoverColor
    
    // Haptic feedback processes
    Process {
        id: hapticOpen
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic.py", config.hapticOpen]
    }
    
    Process {
        id: hapticHover
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic.py", config.hapticHover]
    }
    
    Process {
        id: hapticSelect
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic.py", config.hapticSelect]
    }
    
    // Action execution process
    Process {
        id: actionProcess
        command: ["bash", "-c", ""]
    }
    
    function executeAction(index: int) {
        if (index >= 0 && index < config.items.length) {
            const action = config.items[index].action
            actionProcess.command = ["bash", "-c", "cd ~ && " + action + " &"]
            actionProcess.running = true
        }
    }
    
    visible: false
    color: "transparent"
    
    // Full screen overlay
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    
    // Wayland layer shell configuration
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "actionmenu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    
    // Ignore exclusive zones from other panels (like your bar)
    exclusionMode: ExclusionMode.Ignore
    
    // Focus grab for Hyprland - dismisses when clicking outside
    HyprlandFocusGrab {
        id: focusGrab
        active: radialMenuWindow.visible
        windows: [radialMenuWindow]
        onCleared: radialMenuWindow.close()
    }
    
    // Process to get cursor position from hyprctl
    Process {
        id: cursorProcess
        command: ["hyprctl", "cursorpos"]
        running: false
        
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(", ")
                if (parts.length !== 2) return
                
                const globalX = parseInt(parts[0])
                const globalY = parseInt(parts[1])
                
                for (let i = 0; i < Hyprland.monitors.values.length; i++) {
                    const mon = Hyprland.monitors.values[i]
                    const scaledWidth = mon.width / mon.scale
                    const scaledHeight = mon.height / mon.scale
                    
                    if (globalX >= mon.x && globalX < mon.x + scaledWidth &&
                        globalY >= mon.y && globalY < mon.y + scaledHeight) {
                        for (let j = 0; j < Quickshell.screens.length; j++) {
                            const scr = Quickshell.screens[j]
                            if (scr.name === mon.name) {
                                radialMenuWindow.screen = scr
                                radialMenuWindow.cursorX = globalX - mon.x
                                radialMenuWindow.cursorY = globalY - mon.y
                                break
                            }
                        }
                        break
                    }
                }
                
                radialMenuWindow.visible = true
                focusItem.forceActiveFocus()
                hapticOpen.running = true
            }
        }
    }
    
    function open() {
        cursorProcess.running = true
    }
    
    function close() {
        visible = false
        hoveredIndex = -1
        hapticSelect.running = true
    }
    
    function selectCurrent() {
        if (hoveredIndex >= 0) {
            executeAction(hoveredIndex)
        }
        close()
    }
    
    function toggle() {
        if (visible) {
            close()
        } else {
            open()
        }
    }
    
    // Get index of circle nearest to angle
    function getHoveredIndex(mouseX: real, mouseY: real): int {
        const dx = mouseX - cursorX
        const dy = mouseY - cursorY
        const distance = Math.sqrt(dx * dx + dy * dy)
        
        // Minimum distance to start selecting (dead zone in center)
        const minDist = menuRadius - circleSize
        
        if (distance < minDist) {
            return -1
        }
        
        // Calculate angle and find nearest circle (no max distance)
        let angle = Math.atan2(dx, -dy) * 180 / Math.PI
        angle = (angle + 360) % 360
        
        const segmentSize = 360 / itemCount
        const index = Math.floor((angle + segmentSize / 2) % 360 / segmentSize)
        
        return index
    }
    
    // Focus item for keyboard input
    Item {
        id: focusItem
        focus: true
        Keys.onEscapePressed: radialMenuWindow.close()
    }
    
    // Mouse tracking
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        
        onPositionChanged: mouse => {
            const newIndex = radialMenuWindow.getHoveredIndex(mouse.x, mouse.y)
            if (newIndex !== radialMenuWindow.hoveredIndex && newIndex >= 0) {
                hapticHover.running = true
            }
            radialMenuWindow.hoveredIndex = newIndex
        }
        
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                radialMenuWindow.close()
                return
            }
            
            if (radialMenuWindow.hoveredIndex >= 0) {
                radialMenuWindow.executeAction(radialMenuWindow.hoveredIndex)
            }
            radialMenuWindow.close()
        }
    }
    
    // Visual: 8 circles arranged radially
    Item {
        id: menuVisual
        x: radialMenuWindow.cursorX - radialMenuWindow.menuRadius - radialMenuWindow.circleSize / 2
        y: radialMenuWindow.cursorY - radialMenuWindow.menuRadius - radialMenuWindow.circleSize / 2
        width: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) * 2
        height: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) * 2
        
        Repeater {
            model: radialMenuWindow.itemCount
            
            Rectangle {
                id: circleItem
                
                required property int index
                
                property real angle: index * (360 / radialMenuWindow.itemCount) - 90
                property real angleRad: angle * Math.PI / 180
                property bool isHovered: radialMenuWindow.hoveredIndex === index
                property var itemData: config.items[index]
                
                x: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) + 
                   radialMenuWindow.menuRadius * Math.cos(angleRad) - width / 2
                y: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) + 
                   radialMenuWindow.menuRadius * Math.sin(angleRad) - height / 2
                
                width: radialMenuWindow.circleSize
                height: radialMenuWindow.circleSize
                radius: width / 2
                
                color: isHovered ? radialMenuWindow.itemHoverColor : radialMenuWindow.itemColor
                
                Text {
                    anchors.centerIn: parent
                    text: circleItem.itemData.icon
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: radialMenuWindow.circleSize * 0.45
                    color: config.iconColor
                }
            }
        }
    }
}
