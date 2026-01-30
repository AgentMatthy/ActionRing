import QtQuick

QtObject {
    // Haptic feedback patterns (see mx4haptic.py for available patterns)
    // Available: click, tick, bump, double_click, hold, release, error, success
    readonly property string hapticOpen: ""
    readonly property string hapticHover: "3"
    readonly property string hapticSelect: "1"
    readonly property string hapticClose: "8"
    
    // Visual configuration
    readonly property int menuRadius: 90
    readonly property int circleSize: 58
    
    // Colors
    readonly property color itemColor: "#000000"
    readonly property color itemHoverColor: "#333333"
    readonly property color iconColor: "#ffffff"
    
    // Menu items: icon (nerdfont glyph) and action (bash command)
    readonly property var items: [
        { icon: "", action: "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%+; paplay /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga" },                          // 0: top - browser
        { icon: "", action: "kitty yazi" },                           // 1: top-right - files
        { icon: "", action: "kitty" },                            // 2: right - terminal
        { icon: "", action: "neovide" },                             // 3: bottom-right - editor
        { icon: "", action: "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%-; paplay /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga" },                          // 4: bottom - music
        { icon: "", action: "" },                          // 5: bottom-left - chat
        { icon: "", action: "" },  // 6: left - toggle float
        { icon: "", action: "" },                    // 7: top-left - color picker
    ]
    
    // Convenience property for item count
    readonly property int itemCount: items.length
}
