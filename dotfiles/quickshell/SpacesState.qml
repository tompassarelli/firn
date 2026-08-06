pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mirrors spaced's state snapshot. tail -F, not FileView: spaced replaces
// state.json by atomic rename, which silently kills a file watch.
Singleton {
    id: root
    property bool available: false
    property string current: ""
    property string currentLabel: ""
    property var memberOrdinals: ({})
    property var floatingIds: ({})

    Process {
        running: true
        command: ["tail", "-F", "-n", "1",
                  Quickshell.env("HOME") + "/.local/state/spaces/state.json"]
        stdout: SplitParser {
            onRead: data => root.parse(data)
        }
    }

    function parse(raw) {
        try {
            const st = JSON.parse(raw)
            const ords = {}
            const floats = {}
            let label = st.current
            for (const sp of st.spaces || []) {
                if (sp.id === st.current) {
                    label = sp.label || sp.id
                    let i = 1
                    for (const w of sp.workspaces || []) ords[w.id] = i++
                }
            }
            for (const w of st.floating || []) floats[w.id] = true
            root.current = st.current || ""
            root.currentLabel = label || ""
            root.memberOrdinals = ords
            root.floatingIds = floats
            root.available = true
        } catch (e) {
            // partial line during a replace; next snapshot line corrects
        }
    }
}
