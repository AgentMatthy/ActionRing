import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root
    
    RadialMenu {
        id: radialMenu
        
        // Right-click while the ring is open opens the configuration editor
        onRequestConfigEditor: configEditor.openEditor()
    }
    
    // Configuration GUI (shares the script dir; hot-reloads the menu on save)
    ConfigEditor {
        id: configEditor
        scriptDir: radialMenu._scriptDir
        radialMenu: radialMenu
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
        
        function select(): void {
            radialMenu.selectCurrent()
        }
        
        function isOpen(): bool {
            return radialMenu.visible
        }
    }
    
    // IPC handler for the configuration editor
    IpcHandler {
        target: "config"
        
        function open(): void {
            configEditor.openEditor()
        }
        
        function close(): void {
            configEditor.closeEditor()
        }
        
        function toggle(): void {
            if (configEditor.visible) configEditor.closeEditor()
            else configEditor.openEditor()
        }
    }
}
