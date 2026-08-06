pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mirrors spaced's state snapshot; when the daemon is down (no/stale file)
// `available` stays false and the bar falls back to the plain workspace row.
Singleton {
    id: root
    property bool available: false
    property string current: ""
    property string currentLabel: ""
    property var memberOrdinals: ({})
    property var floatingIds: ({})

    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.local/state/spaces/state.json"
        watchChanges: true
        onTextChanged: root.parse(text())
        onLoaded: root.parse(text())
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
            root.available = false
        }
    }
}
