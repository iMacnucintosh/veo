import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Veo
import "components"

// Veo: the video fills the window; the controls come up with the pointer and go away while it rests.
Window {
    id: win

    width: 1280
    height: 720
    minimumWidth: 480
    minimumHeight: 300
    visible: true
    color: "#000000"
    title: player.loaded ? win.displayName + " — Veo" : "Veo"

    readonly property bool fullscreen: visibility === Window.FullScreen
    // The file's own title when it has one; mpv falls back to the file name, shown here without its extension
    readonly property string displayName: player.title && player.title !== player.source.split("/").pop()
                                          ? player.title : Library.fileName(player.source)
    readonly property string nextFile: player.source ? Library.neighbour(player.source, 1) : ""
    readonly property string previousFile: player.source ? Library.neighbour(player.source, -1) : ""
    // Which card is open over the picture: "", "audio", "subtitles" or "speed"
    property string menu: ""
    property bool awake: true
    readonly property bool chromeShown: !player.loaded || player.paused || player.ended || awake || menu !== ""
                                        || seekBar.active || DevShotUi !== ""

    // Subtitles move up while the controls are on screen (mpv measures the margin on a 720-line picture)
    onChromeShownChanged: player.setMpvProperty("sub-margin-y", String(Math.round((win.chromeShown ? 150 : 34) * 720 / Math.max(1, win.height))))

    function formatTime(seconds) {
        const s = Math.max(0, Math.floor(seconds))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const rest = s % 60
        const two = (n) => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + two(m) + ":" + two(rest) : m + ":" + two(rest)
    }

    function wake() {
        win.awake = true
        idleTimer.restart()
    }

    function toggleFullscreen() {
        win.visibility = win.fullscreen ? Window.Windowed : Window.FullScreen
    }

    function openFile(path) {
        if (!path)
            return
        win.menu = ""
        nextUp.dismissed = false
        player.open(path)
        win.wake()
    }

    function showOsd(text, icon) {
        osd.show(text, icon || "")
    }

    function changeVolume(delta) {
        player.muted = false
        player.volume = Math.max(0, Math.min(100, Math.round(player.volume + delta)))
        win.showOsd(qsTr("Volume %1%").arg(Math.round(player.volume)), player.volume === 0 ? "volume_off" : "volume_up")
    }

    function changeSpeed(value) {
        player.speed = Math.max(0.25, Math.min(3, value))
    }

    function changeSubDelay(delta) {
        player.subDelay = Math.round((player.subDelay + delta) * 10) / 10
    }

    // Track languages in the language of the interface; the less common ones by their English name
    function languageName(code) {
        const names = {
            es: qsTr("Spanish"), spa: qsTr("Spanish"), en: qsTr("English"), eng: qsTr("English"),
            fr: qsTr("French"), fre: qsTr("French"), fra: qsTr("French"), de: qsTr("German"), ger: qsTr("German"), deu: qsTr("German"),
            it: qsTr("Italian"), ita: qsTr("Italian"), pt: qsTr("Portuguese"), por: qsTr("Portuguese"),
            ja: qsTr("Japanese"), jpn: qsTr("Japanese"), ko: qsTr("Korean"), kor: qsTr("Korean"),
            zh: qsTr("Chinese"), chi: qsTr("Chinese"), zho: qsTr("Chinese"), ru: qsTr("Russian"), rus: qsTr("Russian"),
            ca: qsTr("Catalan"), cat: qsTr("Catalan"), eu: qsTr("Basque"), baq: qsTr("Basque"), eus: qsTr("Basque"),
            gl: qsTr("Galician"), glg: qsTr("Galician"), nl: qsTr("Dutch"), dut: qsTr("Dutch"), nld: qsTr("Dutch"),
            pl: qsTr("Polish"), pol: qsTr("Polish"), ar: qsTr("Arabic"), ara: qsTr("Arabic"), hi: qsTr("Hindi"), hin: qsTr("Hindi")
        }
        const key = (code || "").toLowerCase()
        return names[key] || Library.languageName(key)
    }

    function codecName(codec) {
        const names = { subrip: "SRT", ass: "ASS", ssa: "SSA", webvtt: "VTT", mov_text: "TX3G", hdmv_pgs_subtitle: "PGS",
                        dvd_subtitle: "VobSub", eac3: "E-AC-3", ac3: "AC-3", truehd: "TrueHD", dts: "DTS", flac: "FLAC",
                        opus: "Opus", vorbis: "Vorbis", aac: "AAC", mp3: "MP3" }
        const key = (codec || "").toLowerCase()
        return names[key] || key.toUpperCase()
    }

    function trackLabel(t, kind) {
        const lang = win.languageName(t.lang || "")
        if (t.title && lang && t.title.toLowerCase().indexOf(lang.toLowerCase()) < 0)
            return lang + " — " + t.title
        return t.title || lang || (kind === "audio" ? qsTr("Track %1").arg(t.id) : qsTr("Subtitles %1").arg(t.id))
    }

    function channelsLabel(n) {
        switch (n) {
        case 1: return qsTr("Mono")
        case 2: return qsTr("Stereo")
        case 6: return "5.1"
        case 8: return "7.1"
        default: return n > 0 ? qsTr("%1 channels").arg(n) : ""
        }
    }

    function audioDetail(t) {
        return [channelsLabel(t.channels || 0), win.codecName(t.codec), t.isDefault ? qsTr("Default") : ""]
            .filter((p) => p.length > 0).join(" · ")
    }

    function subtitleDetail(t) {
        return [t.forced ? qsTr("Forced") : "", t.external ? qsTr("From a file") : "", win.codecName(t.codec)]
            .filter((p) => p.length > 0).join(" · ")
    }

    function cycleTrack(kind) {
        const list = kind === "audio" ? player.audioTracks : player.subtitleTracks
        const current = kind === "audio" ? player.audioId : player.subtitleId
        if (!list.length)
            return
        // Subtitles go round through "off" too
        const ids = list.map((t) => t.id)
        if (kind === "subtitles")
            ids.push(0)
        const next = ids[(ids.indexOf(current) + 1) % ids.length]
        if (kind === "audio") {
            player.setAudioTrack(next)
            const t = list.find((x) => x.id === next)
            win.showOsd(qsTr("Audio: %1").arg(win.trackLabel(t, "audio")), "audiotrack")
        } else {
            player.setSubtitleTrack(next)
            const t = list.find((x) => x.id === next)
            win.showOsd(t ? qsTr("Subtitles: %1").arg(win.trackLabel(t, "subtitles")) : qsTr("Subtitles off"), "subtitles")
        }
    }

    Component.onCompleted: {
        player.volume = Library.volume
        if (StartFile) {
            win.visibility = Window.FullScreen
            win.openFile(StartFile)
        }
        if (DevShotUi === "audio" || DevShotUi === "subtitles" || DevShotUi === "speed")
            devMenu.start()
    }

    Timer {
        id: devMenu
        interval: 1200
        onTriggered: win.menu = DevShotUi
    }

    Mpv {
        id: player
        anchors.fill: parent

        onVolumeChanged: Library.volume = volume
        onFileLoaded: (resumedAt) => {
            if (resumedAt > 5)
                win.showOsd(qsTr("Resuming at %1").arg(win.formatTime(resumedAt)), "history")
        }
        onSpeedChanged: {
            if (loaded)
                win.showOsd(qsTr("Speed %1×").arg(Number(speed).toLocaleString(Qt.locale(), "f", speed % 1 === 0 ? 0 : 2).replace(/0$/, "")), "speed")
        }
        onSubDelayChanged: {
            if (loaded)
                win.showOsd(qsTr("Subtitle delay %1 s").arg((subDelay > 0 ? "+" : "") + Number(subDelay).toLocaleString(Qt.locale(), "f", 1)), "subtitles")
        }
    }

    Timer {
        id: idleTimer
        interval: 2500
        running: true
        onTriggered: win.awake = false
    }

    // A single click pauses; a double click goes full screen (the click waits a moment to know which)
    Timer {
        id: clickTimer
        interval: 220
        onTriggered: {
            if (player.loaded)
                player.togglePause()
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: win.chromeShown ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: win.wake()
        onClicked: {
            win.wake()
            if (win.menu !== "") {
                win.menu = ""
                return
            }
            clickTimer.restart()
        }
        onDoubleClicked: {
            clickTimer.stop()
            win.toggleFullscreen()
        }
        onWheel: (wheel) => {
            win.wake()
            win.changeVolume(wheel.angleDelta.y > 0 ? 5 : -5)
        }
    }

    DropArea {
        anchors.fill: parent
        onDropped: (drop) => {
            if (drop.hasUrls) {
                const path = decodeURIComponent(drop.urls[0].toString().replace(/^file:\/\//, ""))
                if (/\.(srt|ass|ssa|vtt|sub)$/i.test(path) && player.loaded) {
                    player.addSubtitle(path)
                    win.showOsd(qsTr("Subtitles added"), "subtitles")
                } else {
                    win.openFile(path)
                }
            }
        }
    }

    // Nothing open yet
    ColumnLayout {
        anchors.centerIn: parent
        visible: !player.source
        spacing: 18

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 112
            Layout.preferredHeight: 112
            radius: 34
            color: Theme.primaryContainer

            MaterialIcon {
                anchors.centerIn: parent
                icon: "movie"
                size: 56
                fill: 1
                colour: Theme.onPrimaryContainer
            }
        }

        VText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Drop a video here")
            font.pixelSize: 18
            font.weight: Font.Medium
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: openRow.implicitWidth + 40
            implicitHeight: 44
            radius: 22
            color: Theme.primary

            RowLayout {
                id: openRow
                anchors.centerIn: parent
                spacing: 8
                MaterialIcon {
                    icon: "folder_open"
                    size: 20
                    colour: Theme.onPrimary
                }
                VText {
                    text: qsTr("Open a video")
                    color: Theme.onPrimary
                    font.weight: Font.Medium
                }
            }

            StateLayer {
                radius: parent.radius
                color: Theme.onPrimary
                onClicked: Library.pick("video", "", qsTr("Open a video"), qsTr("Open"))
            }
        }
    }

    VText {
        anchors.centerIn: parent
        visible: player.error !== ""
        width: Math.min(parent.width - 80, 560)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: qsTr("This file could not be played:\n%1").arg(Library.fileName(player.error))
    }

    Connections {
        target: Library
        function onPicked(kind, path) {
            if (!path)
                return
            if (kind === "subtitle") {
                player.addSubtitle(path)
                win.showOsd(qsTr("Subtitles added"), "subtitles")
            } else {
                win.openFile(path)
            }
        }
    }

    // Top: the title
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 110
        visible: player.loaded
        opacity: win.chromeShown ? 1 : 0
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.6) }
            GradientStop { position: 1; color: "transparent" }
        }

        Behavior on opacity {
            NumberAnimation { duration: 220 }
        }

        VText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 28
            text: win.displayName
            font.pixelSize: 20
            font.weight: Font.Medium
        }
    }

    // Bottom: progress and controls
    Rectangle {
        id: bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 150
        visible: player.loaded || player.source !== ""
        opacity: win.chromeShown ? 1 : 0
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.72) }
        }

        Behavior on opacity {
            NumberAnimation { duration: 220 }
        }

        // The pointer resting on the controls keeps them up
        HoverHandler {
            onHoveredChanged: {
                if (hovered)
                    win.wake()
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.bottomMargin: 14
            spacing: 6

            SeekBar {
                id: seekBar
                Layout.fillWidth: true
                position: player.position
                duration: player.duration
                formatTime: win.formatTime
                onSeekTo: (seconds) => {
                    win.wake()
                    player.seek(seconds, false)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                IconButton {
                    icon: "skip_previous"
                    colour: "#ffffff"
                    enabled: win.previousFile !== ""
                    onClicked: win.openFile(win.previousFile)
                }
                IconButton {
                    size: 48
                    iconSize: 32
                    icon: player.ended ? "replay" : (player.paused ? "play_arrow" : "pause")
                    colour: "#ffffff"
                    onClicked: player.togglePause()
                }
                IconButton {
                    icon: "skip_next"
                    colour: "#ffffff"
                    enabled: win.nextFile !== ""
                    onClicked: win.openFile(win.nextFile)
                }

                VText {
                    Layout.leftMargin: 10
                    text: win.formatTime(player.position) + " / " + win.formatTime(player.duration)
                    font.pixelSize: 13
                    font.features: { "tnum": 1 }
                }

                Item {
                    Layout.fillWidth: true
                }

                IconButton {
                    icon: player.muted || player.volume === 0 ? "volume_off" : (player.volume < 50 ? "volume_down" : "volume_up")
                    colour: "#ffffff"
                    onClicked: player.muted = !player.muted
                }

                Item {
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 28

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.25)

                        Rectangle {
                            width: parent.width * (player.muted ? 0 : player.volume / 100)
                            height: parent.height
                            radius: parent.radius
                            color: "#ffffff"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function set(x) {
                            player.muted = false
                            player.volume = Math.round(Math.max(0, Math.min(1, x / width)) * 100)
                        }
                        onPressed: (mouse) => set(mouse.x)
                        onPositionChanged: (mouse) => {
                            if (pressed)
                                set(mouse.x)
                        }
                    }
                }

                // Speed: shows itself when it is not 1×
                Rectangle {
                    Layout.leftMargin: 6
                    implicitWidth: speedLabel.implicitWidth + 20
                    implicitHeight: 32
                    radius: 16
                    color: win.menu === "speed" ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.35)

                    VText {
                        id: speedLabel
                        anchors.centerIn: parent
                        text: Number(player.speed).toLocaleString(Qt.locale(), "f", player.speed % 1 === 0 ? 0 : 2).replace(/0$/, "") + "×"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    StateLayer {
                        radius: parent.radius
                        color: "#ffffff"
                        onClicked: win.menu = win.menu === "speed" ? "" : "speed"
                    }
                }

                IconButton {
                    icon: "audiotrack"
                    colour: "#ffffff"
                    bg: win.menu === "audio" ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
                    enabled: player.audioTracks.length > 0
                    onClicked: win.menu = win.menu === "audio" ? "" : "audio"
                }
                IconButton {
                    icon: player.subtitleId > 0 ? "subtitles" : "subtitles_off"
                    colour: "#ffffff"
                    bg: win.menu === "subtitles" ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
                    onClicked: win.menu = win.menu === "subtitles" ? "" : "subtitles"
                }
                IconButton {
                    icon: win.fullscreen ? "fullscreen_exit" : "fullscreen"
                    colour: "#ffffff"
                    onClicked: win.toggleFullscreen()
                }
            }
        }
    }

    // Menus, above the buttons that open them
    MenuCard {
        id: audioMenu
        anchors.right: parent.right
        anchors.bottom: bottom.top
        anchors.rightMargin: 24
        anchors.bottomMargin: -40
        open: win.menu === "audio"
        title: qsTr("Audio")
        entries: player.audioTracks.map((t) => ({
            label: win.trackLabel(t, "audio"),
            detail: win.audioDetail(t),
            checked: t.id === player.audioId,
            action: () => player.setAudioTrack(t.id)
        }))
        onPicked: win.menu = ""
    }

    MenuCard {
        id: subtitleMenu
        anchors.right: parent.right
        anchors.bottom: bottom.top
        anchors.rightMargin: 24
        anchors.bottomMargin: -40
        open: win.menu === "subtitles"
        title: qsTr("Subtitles")
        entries: [{
            label: qsTr("Off"),
            detail: "",
            checked: player.subtitleId === 0,
            action: () => player.setSubtitleTrack(0)
        }].concat(player.subtitleTracks.map((t) => ({
            label: win.trackLabel(t, "subtitles"),
            detail: win.subtitleDetail(t),
            checked: t.id === player.subtitleId,
            action: () => player.setSubtitleTrack(t.id)
        }))).concat([{
            label: qsTr("Load from a file"),
            detail: qsTr("SRT, ASS, VTT"),
            checked: false,
            action: () => Library.pick("subtitle", player.source.substring(0, player.source.lastIndexOf("/")), qsTr("Choose subtitles"), qsTr("Load"))
        }])
        onPicked: win.menu = ""

        footer: [
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 4
                Layout.topMargin: 4
                visible: player.subtitleId > 0
                spacing: 4

                VText {
                    Layout.fillWidth: true
                    text: qsTr("Delay")
                    color: Theme.onSurface
                }
                IconButton {
                    size: 32
                    iconSize: 20
                    icon: "remove"
                    onClicked: win.changeSubDelay(-0.1)
                }
                VText {
                    Layout.preferredWidth: 58
                    horizontalAlignment: Text.AlignHCenter
                    text: (player.subDelay > 0 ? "+" : "") + Number(player.subDelay).toLocaleString(Qt.locale(), "f", 1) + " s"
                    color: Theme.onSurface
                    font.features: { "tnum": 1 }
                }
                IconButton {
                    size: 32
                    iconSize: 20
                    icon: "add"
                    onClicked: win.changeSubDelay(0.1)
                }
            }
        ]
    }

    MenuCard {
        id: speedMenu
        anchors.right: parent.right
        anchors.bottom: bottom.top
        anchors.rightMargin: 24
        anchors.bottomMargin: -40
        width: 200
        open: win.menu === "speed"
        title: qsTr("Speed")
        entries: [0.5, 0.75, 1, 1.25, 1.5, 2].map((v) => ({
            label: v === 1 ? qsTr("Normal") : Number(v).toLocaleString(Qt.locale(), "f", 2).replace(/0$/, "") + "×",
            detail: "",
            checked: Math.abs(player.speed - v) < 0.001,
            action: () => win.changeSpeed(v)
        }))
        onPicked: win.menu = ""
    }

    // Short notices at the top (volume, speed, the track chosen)
    Rectangle {
        id: osd

        property string icon: ""

        function show(text, icon) {
            osdText.text = text
            osd.icon = icon
            osd.opacity = 1
            osdTimer.restart()
        }

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 72
        width: osdRow.implicitWidth + 32
        height: 44
        radius: 22
        color: Qt.rgba(0, 0, 0, 0.7)
        opacity: 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: 180 }
        }

        Timer {
            id: osdTimer
            interval: 1400
            onTriggered: osd.opacity = 0
        }

        RowLayout {
            id: osdRow
            anchors.centerIn: parent
            spacing: 10
            MaterialIcon {
                visible: osd.icon !== ""
                icon: osd.icon
                size: 20
                colour: "#ffffff"
            }
            VText {
                id: osdText
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
            }
        }
    }

    // At the end: the next file of the folder, played after a countdown unless cancelled
    Rectangle {
        id: nextUp

        property bool dismissed: false
        property real remaining: 1
        readonly property bool shown: (player.ended || DevShotUi === "next") && win.nextFile !== "" && !dismissed

        anchors.right: parent.right
        anchors.bottom: bottom.top
        anchors.rightMargin: 24
        anchors.bottomMargin: 8
        width: 340
        height: nextCol.implicitHeight + 32
        radius: 24
        color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.96)
        opacity: shown ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        onShownChanged: {
            remaining = 1
            if (shown && DevShotUi !== "next")
                countdown.restart()
            else
                countdown.stop()
        }

        NumberAnimation {
            id: countdown
            target: nextUp
            property: "remaining"
            from: 1
            to: 0
            duration: 6000
            onFinished: win.openFile(win.nextFile)
        }

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: nextCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 4

            VText {
                text: qsTr("Up next")
                color: Theme.onSurfaceVariant
                font.pixelSize: 12
                font.weight: Font.Medium
            }
            VText {
                Layout.fillWidth: true
                text: Library.fileName(win.nextFile)
                color: Theme.onSurface
                font.pixelSize: 16
                font.weight: Font.Medium
                elide: Text.ElideMiddle
            }

            // Time left before it starts
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 8
                implicitHeight: 4
                radius: 2
                color: Theme.surfaceContainerHighest
                Rectangle {
                    width: parent.width * (1 - nextUp.remaining)
                    height: parent.height
                    radius: 2
                    color: Theme.primary
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    implicitWidth: cancelLabel.implicitWidth + 32
                    implicitHeight: 38
                    radius: 19
                    color: "transparent"
                    VText {
                        id: cancelLabel
                        anchors.centerIn: parent
                        text: qsTr("Cancel")
                        color: Theme.primary
                        font.weight: Font.Medium
                    }
                    StateLayer {
                        radius: parent.radius
                        color: Theme.primary
                        onClicked: nextUp.dismissed = true
                    }
                }

                Rectangle {
                    implicitWidth: playRow.implicitWidth + 32
                    implicitHeight: 38
                    radius: 19
                    color: Theme.primary
                    RowLayout {
                        id: playRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialIcon {
                            icon: "play_arrow"
                            size: 20
                            fill: 1
                            colour: Theme.onPrimary
                        }
                        VText {
                            text: qsTr("Play now")
                            color: Theme.onPrimary
                            font.weight: Font.Medium
                        }
                    }
                    StateLayer {
                        radius: parent.radius
                        color: Theme.onPrimary
                        onClicked: win.openFile(win.nextFile)
                    }
                }
            }
        }
    }

    // Keyboard
    Shortcut { sequences: ["Space", "K"]; onActivated: { player.togglePause(); win.wake() } }
    Shortcut { sequences: ["Right"]; onActivated: { player.seek(10); win.wake() } }
    Shortcut { sequences: ["Left"]; onActivated: { player.seek(-10); win.wake() } }
    Shortcut { sequences: ["Shift+Right"]; onActivated: { player.seek(60); win.wake() } }
    Shortcut { sequences: ["Shift+Left"]; onActivated: { player.seek(-60); win.wake() } }
    Shortcut { sequences: ["Up"]; onActivated: win.changeVolume(5) }
    Shortcut { sequences: ["Down"]; onActivated: win.changeVolume(-5) }
    Shortcut {
        sequences: ["M"]
        onActivated: {
            player.muted = !player.muted
            win.showOsd(player.muted ? qsTr("Muted") : qsTr("Volume %1%").arg(Math.round(player.volume)), player.muted ? "volume_off" : "volume_up")
        }
    }
    Shortcut { sequences: ["F", "F11"]; onActivated: win.toggleFullscreen() }
    Shortcut {
        sequences: ["Escape"]
        onActivated: {
            if (win.menu !== "")
                win.menu = ""
            else if (win.fullscreen)
                win.toggleFullscreen()
        }
    }
    Shortcut { sequences: ["N"]; enabled: win.nextFile !== ""; onActivated: win.openFile(win.nextFile) }
    Shortcut { sequences: ["P"]; enabled: win.previousFile !== ""; onActivated: win.openFile(win.previousFile) }
    Shortcut { sequences: ["]"]; onActivated: win.changeSpeed(player.speed + 0.25) }
    Shortcut { sequences: ["["]; onActivated: win.changeSpeed(player.speed - 0.25) }
    Shortcut { sequences: ["Backspace"]; onActivated: win.changeSpeed(1) }
    Shortcut { sequences: ["X"]; onActivated: win.changeSubDelay(0.1) }
    Shortcut { sequences: ["Z"]; onActivated: win.changeSubDelay(-0.1) }
    Shortcut { sequences: ["A"]; onActivated: win.cycleTrack("audio") }
    Shortcut { sequences: ["S"]; onActivated: win.cycleTrack("subtitles") }
    Shortcut { sequences: ["Home"]; onActivated: player.seek(0, false) }
    Shortcut { sequences: ["O", StandardKey.Open]; onActivated: Library.pick("video", "", qsTr("Open a video"), qsTr("Open")) }
    Shortcut { sequences: ["Q", StandardKey.Quit, StandardKey.Close]; onActivated: Qt.quit() }
}
