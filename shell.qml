import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root
    
    RadialMenu {
        id: radialMenu
    }
    
    // IPC handler for command line control
    IpcHandler {
        target: "menu"
        
        function open(): void {
            radialMenu.open()
        }
        
        function close(): void {
            radialMenu.close()
        }
        
        function toggle(): void {
            radialMenu.toggle()
        }
        
        function isOpen(): bool {
            return radialMenu.visible
        }
    }
}
