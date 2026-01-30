import QtQuick

QtObject {
    // Haptic feedback patterns (see mx4haptic.py for available patterns)
    // Available: click, tick, bump, double_click, hold, release, error, success
    readonly property string hapticOpen: "bump"
    readonly property string hapticHover: "tick"
    readonly property string hapticSelect: "click"
    
    // Visual configuration
    readonly property int menuRadius: 80
    readonly property int circleSize: 58
    
    // Colors
    readonly property color itemColor: "#000000"
    readonly property color itemHoverColor: "#333333"
    readonly property color iconColor: "#ffffff"
    
    // Menu items: icon (nerdfont glyph) and action (bash command)
    readonly property var items: [
        { icon: "", action: "" },                          // 0: top - browser
        { icon: "", action: "kitty yazi" },                           // 1: top-right - files
        { icon: "", action: "kitty" },                            // 2: right - terminal
        { icon: "", action: "neovide" },                             // 3: bottom-right - editor
        { icon: "", action: "" },                          // 4: bottom - music
        { icon: "", action: "" },                          // 5: bottom-left - chat
        { icon: "", action: "" },  // 6: left - toggle float
        { icon: "", action: "" },                    // 7: top-left - color picker
    ]
    
    // Convenience property for item count
    readonly property int itemCount: items.length
}
