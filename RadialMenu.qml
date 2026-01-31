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
    property int hoveredIndex: -1
    
    // Current menu state
    property var currentItems: config.items
    property int itemCount: currentItems.length
    property var menuStack: []  // Stack of {items, cursorX, cursorY} for submenu navigation
    
    // Animation state
    property bool isOpen: false
    property bool isTransitioning: false  // True during submenu transitions
    property int transitionDirection: 1   // 1 = opening submenu, -1 = closing submenu
    
    // Suppress initial mouse movement after menu opens
    property bool ignoreFirstMove: false
    
    // Cursor position when menu was opened (screen-relative)
    property real cursorX: 0
    property real cursorY: 0
    
    // Colors from Config.qml
    property color itemColor: config.itemColor
    property color itemHoverColor: config.itemHoverColor
    
    // Haptic feedback processes (uses daemon via Unix socket for instant response)
    Process {
        id: hapticOpen
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", config.hapticOpen]
    }
    
    Process {
        id: hapticHover
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", config.hapticHover]
    }
    
    Process {
        id: hapticSelect
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", config.hapticSelect]
    }
    
    Process {
        id: hapticClose
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", config.hapticClose]
    }
    
    // Keepalive control - wakes device when menu opens, sleeps when closes
    Process {
        id: hapticWake
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", "wake"]
    }
    
    Process {
        id: hapticSleep
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", "sleep"]
    }
    
    // Action execution process
    Process {
        id: actionProcess
        command: ["bash", "-c", ""]
    }
    
    function executeAction(index: int) {
        if (index >= 0 && index < currentItems.length) {
            const item = currentItems[index]
            
            // Check if this is a submenu trigger
            if (item.submenu !== undefined) {
                // Will be handled by hover, not click
                return
            }
            
            // Check if this is a close submenu action
            if (item.closesubmenu === true) {
                // Will be handled by hover, not click
                return
            }
            
            // Execute the action
            if (item.action && item.action !== "") {
                actionProcess.command = ["bash", "-c", "cd ~ && " + item.action + " &"]
                actionProcess.running = true
            }
        }
    }
    
    function openSubmenu(submenuName: string, newCursorX: real, newCursorY: real) {
        const submenuItems = config.submenus[submenuName]
        if (submenuItems === undefined) {
            console.log("Submenu not found:", submenuName)
            return
        }
        
        // Push current state to stack
        menuStack.push({
            items: currentItems,
            cursorX: cursorX,
            cursorY: cursorY
        })
        
        // Start transition animation
        transitionDirection = 1
        isTransitioning = true
        
        // Store new state for after animation
        pendingItems = submenuItems
        pendingCursorX = newCursorX
        pendingCursorY = newCursorY
        
        transitionOutTimer.start()
        hapticOpen.running = true
    }
    
    function closeSubmenu(newCursorX: real, newCursorY: real) {
        if (menuStack.length === 0) {
            // No parent menu, just close
            close()
            return
        }
        
        // Pop previous state from stack
        const prevState = menuStack.pop()
        
        // Start transition animation
        transitionDirection = -1
        isTransitioning = true
        
        // Store new state for after animation
        pendingItems = prevState.items
        pendingCursorX = newCursorX
        pendingCursorY = newCursorY
        
        transitionOutTimer.start()
        hapticOpen.running = true
    }
    
    // Pending state for after transition
    property var pendingItems: []
    property real pendingCursorX: 0
    property real pendingCursorY: 0
    
    // Timer to switch menu content mid-transition
    Timer {
        id: transitionOutTimer
        interval: 80  // Wait for out animation
        onTriggered: {
            // Apply the pending state
            radialMenuWindow.currentItems = radialMenuWindow.pendingItems
            radialMenuWindow.itemCount = radialMenuWindow.currentItems.length
            radialMenuWindow.cursorX = radialMenuWindow.pendingCursorX
            radialMenuWindow.cursorY = radialMenuWindow.pendingCursorY
            radialMenuWindow.hoveredIndex = -1
            radialMenuWindow.ignoreFirstMove = true
            
            // Start in animation
            transitionInTimer.start()
        }
    }
    
    Timer {
        id: transitionInTimer
        interval: 10  // Small delay before animating in
        onTriggered: {
            radialMenuWindow.isTransitioning = false
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
                radialMenuWindow.isOpen = true
                focusItem.forceActiveFocus()
                hapticOpen.running = true
            }
        }
    }
    
    function open() {
        hoveredIndex = -1  // Reset selection state before opening
        ignoreFirstMove = true  // Ignore initial mouse position event
        currentItems = config.items  // Reset to main menu
        itemCount = currentItems.length
        menuStack = []  // Clear submenu stack
        hapticWake.running = true  // Wake device immediately before getting cursor
        cursorProcess.running = true
    }
    
    function close() {
        isOpen = false
        hoveredIndex = -1
        menuStack = []  // Clear submenu stack
        hapticClose.running = true
        hapticSleep.running = true  // Stop keepalive
    }
    
    // Hide window after close animation completes
    onIsOpenChanged: {
        if (!isOpen) {
            closeTimer.start()
        }
    }
    
    Timer {
        id: closeTimer
        interval: 100
        onTriggered: {
            radialMenuWindow.visible = false
            // Reset to main menu after window is hidden
            radialMenuWindow.currentItems = config.items
            radialMenuWindow.itemCount = radialMenuWindow.currentItems.length
        }
    }
    
    function selectCurrent() {
        if (hoveredIndex >= 0) {
            executeAction(hoveredIndex)
            hapticSelect.running = true
        } else {
            hapticClose.running = true
        }
        isOpen = false
        hoveredIndex = -1
        menuStack = []
        hapticSleep.running = true  // Stop keepalive
    }
    
    function toggle() {
        if (visible) {
            close()
        } else {
            open()
        }
    }
    
    // Get position of a menu item by index (in screen coordinates)
    function getItemPosition(index: int): var {
        const angle = index * (360 / itemCount) - 90
        const angleRad = angle * Math.PI / 180
        return {
            x: cursorX + menuRadius * Math.cos(angleRad),
            y: cursorY + menuRadius * Math.sin(angleRad)
        }
    }
    
    // Get index of circle based on angle (cursor must reach item distance)
    function getHoveredIndex(mouseX: real, mouseY: real): int {
        const dx = mouseX - cursorX
        const dy = mouseY - cursorY
        const distance = Math.sqrt(dx * dx + dy * dy)
        
        // Dead zone: cursor must reach the inner edge of the item circles
        // Items are at menuRadius, circles have radius circleSize/2
        const minDist = menuRadius - circleSize / 2
        if (distance < minDist) {
            return -1
        }
        
        // Calculate angle and find nearest circle (angle-based, no max distance)
        let angle = Math.atan2(dx, -dy) * 180 / Math.PI
        angle = (angle + 360) % 360
        
        const segmentSize = 360 / itemCount
        const index = Math.floor((angle + segmentSize / 2) % 360 / segmentSize)
        
        return index
    }
    
    // Handle submenu navigation on hover
    function handleHover(index: int) {
        if (index < 0 || index >= currentItems.length) return
        
        const item = currentItems[index]
        
        // Get the position of the hovered item for submenu placement
        const itemPos = getItemPosition(index)
        
        // Check if this opens a submenu
        if (item.submenu !== undefined) {
            openSubmenu(item.submenu, itemPos.x, itemPos.y)
            return
        }
        
        // Check if this closes the current submenu
        if (item.closesubmenu === true) {
            closeSubmenu(itemPos.x, itemPos.y)
            return
        }
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
            // Ignore the first position change after menu opens (prevents phantom selections)
            if (radialMenuWindow.ignoreFirstMove) {
                radialMenuWindow.ignoreFirstMove = false
                return
            }
            
            const newIndex = radialMenuWindow.getHoveredIndex(mouse.x, mouse.y)
            if (newIndex !== radialMenuWindow.hoveredIndex && newIndex >= 0) {
                hapticHover.running = true
                
                // Check for submenu triggers on hover
                radialMenuWindow.handleHover(newIndex)
            }
            radialMenuWindow.hoveredIndex = newIndex
        }
        
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                radialMenuWindow.close()
                return
            }
            
            if (radialMenuWindow.hoveredIndex >= 0) {
                const item = radialMenuWindow.currentItems[radialMenuWindow.hoveredIndex]
                // Don't close if it's a submenu trigger (already handled by hover)
                if (item.submenu !== undefined || item.closesubmenu === true) {
                    return
                }
                radialMenuWindow.executeAction(radialMenuWindow.hoveredIndex)
            }
            radialMenuWindow.close()
        }
    }
    
    // Visual: circles arranged radially
    Item {
        id: menuVisual
        x: radialMenuWindow.cursorX - radialMenuWindow.menuRadius - radialMenuWindow.circleSize / 2
        y: radialMenuWindow.cursorY - radialMenuWindow.menuRadius - radialMenuWindow.circleSize / 2
        width: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) * 2
        height: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) * 2
        
        // Only animate position during submenu transitions (not initial open)
        Behavior on x {
            enabled: radialMenuWindow.isOpen
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutExpo
            }
        }
        
        Behavior on y {
            enabled: radialMenuWindow.isOpen
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutExpo
            }
        }
        
        // Menu open/close/transition animation
        scale: (radialMenuWindow.isOpen && !radialMenuWindow.isTransitioning) ? 1.0 : 0.75
        opacity: (radialMenuWindow.isOpen && !radialMenuWindow.isTransitioning) ? 1.0 : 0.0
        
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutBack
                easing.overshoot: 2
            }
        }
        
        Behavior on opacity {
            NumberAnimation {
                duration: 80
                easing.type: Easing.OutQuart
            }
        }
        
        Repeater {
            model: radialMenuWindow.itemCount
            
            Rectangle {
                id: circleItem
                
                required property int index
                
                property real angle: index * (360 / radialMenuWindow.itemCount) - 90
                property real angleRad: angle * Math.PI / 180
                property bool isHovered: radialMenuWindow.hoveredIndex === index
                property var itemData: radialMenuWindow.currentItems[index]
                
                x: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) + 
                   radialMenuWindow.menuRadius * Math.cos(angleRad) - width / 2
                y: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) + 
                   radialMenuWindow.menuRadius * Math.sin(angleRad) - height / 2
                
                width: radialMenuWindow.circleSize
                height: radialMenuWindow.circleSize
                radius: width / 2
                
                color: isHovered ? radialMenuWindow.itemHoverColor : radialMenuWindow.itemColor
                scale: isHovered ? 1.15 : 1.0
                
                Behavior on color {
                    ColorAnimation {
                        duration: 80
                        easing.type: Easing.OutQuart
                    }
                }
                
                Behavior on scale {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutBack
                        easing.overshoot: 4
                    }
                }
                
                Text {
                    anchors.centerIn: parent
                    text: circleItem.itemData ? circleItem.itemData.icon : ""
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: radialMenuWindow.circleSize * 0.45
                    color: config.iconColor
                    
                    scale: circleItem.isHovered ? 1.1 : 1.0
                    
                    Behavior on scale {
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutBack
                            easing.overshoot: 4
                        }
                    }
                }
            }
        }
    }
}
