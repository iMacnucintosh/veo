import QtQuick

// The progress of the video: drag or click to move, and the time under the pointer while hovering
Item {
    id: root

    property double position: 0
    property double duration: 0
    property var formatTime: (s) => ""
    readonly property bool active: area.containsMouse || area.pressed

    signal seekTo(double seconds)

    implicitHeight: 28

    readonly property real ratio: duration > 0 ? Math.max(0, Math.min(1, position / duration)) : 0
    readonly property real hoverRatio: Math.max(0, Math.min(1, area.mouseX / Math.max(1, width)))

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.active ? 8 : 5
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.25)

        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        // Where the pointer would jump to
        Rectangle {
            visible: area.containsMouse && !area.pressed
            width: parent.width * root.hoverRatio
            height: parent.height
            radius: parent.radius
            color: Qt.rgba(1, 1, 1, 0.22)
        }

        Rectangle {
            width: parent.width * root.ratio
            height: parent.height
            radius: parent.radius
            color: Theme.primary
        }
    }

    Rectangle {
        x: track.width * root.ratio - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.active ? 16 : 0
        height: width
        radius: width / 2
        color: Theme.primary

        Behavior on width {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        visible: area.containsMouse && root.duration > 0
        x: Math.max(0, Math.min(root.width - width, area.mouseX - width / 2))
        y: -height - 8
        width: hoverLabel.implicitWidth + 16
        height: 26
        radius: 13
        color: Qt.rgba(0, 0, 0, 0.75)

        VText {
            id: hoverLabel
            anchors.centerIn: parent
            text: root.formatTime(root.hoverRatio * root.duration)
            font.pixelSize: 12
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function jump(x) {
            if (root.duration > 0)
                root.seekTo(Math.max(0, Math.min(1, x / width)) * root.duration)
        }
        onPressed: (mouse) => jump(mouse.x)
        onPositionChanged: (mouse) => {
            if (pressed)
                jump(mouse.x)
        }
    }
}
