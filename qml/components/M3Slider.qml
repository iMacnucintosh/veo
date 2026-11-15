import QtQuick

// Material 3 expressive slider: an active and an inactive track with rounded ends, split by a tall thin handle with a
// gap on each side. It thickens under the pointer. `value` goes 0…1; moving it emits moved(v) as it goes.
Item {
    id: root

    property real value: 0
    property real trackHeight: 6
    property real activeTrackHeight: 12
    property color activeColour: Theme.primary
    property color inactiveColour: Qt.rgba(1, 1, 1, 0.24)
    property color handleColour: Theme.primary
    // Text above the pointer while hovering (the time of a seek bar); "" for none
    property var hoverText: null
    readonly property bool active: area.containsMouse || area.pressed

    signal moved(real value)

    implicitHeight: 32

    readonly property real shownValue: Math.max(0, Math.min(1, area.pressed ? area.dragValue : value))
    property real thickness: active ? activeTrackHeight : trackHeight
    readonly property real gap: 4
    readonly property real handleWidth: active ? 4 : 3
    readonly property real handleX: shownValue * (width - handleWidth)

    Behavior on thickness {
        SpatialAnim { fast: true }
    }

    // Active track, up to the handle
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        width: Math.max(0, root.handleX - root.gap)
        height: root.thickness
        radius: height / 2
        color: root.activeColour
        visible: width > 0.5
    }

    // Inactive track, after it
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.handleX + root.handleWidth + root.gap
        width: Math.max(0, root.width - x)
        height: root.thickness
        radius: height / 2
        color: root.inactiveColour
        visible: width > 0.5
    }

    // The handle: a thin rounded bar, taller than the track
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.handleX
        width: root.handleWidth
        height: root.thickness + (root.active ? 16 : 10)
        radius: width / 2
        color: root.handleColour

        Behavior on height {
            SpatialAnim { fast: true }
        }
    }

    // The value under the pointer
    Rectangle {
        visible: area.containsMouse && typeof root.hoverText === "function" && root.hoverText(area.hoverValue) !== ""
        x: Math.max(0, Math.min(root.width - width, area.mouseX - width / 2))
        y: -height - 6
        width: hoverLabel.implicitWidth + 20
        height: 28
        radius: 14
        color: Theme.inverseSurface

        VText {
            id: hoverLabel
            anchors.centerIn: parent
            text: typeof root.hoverText === "function" ? root.hoverText(area.hoverValue) : ""
            color: Theme.inverseOnSurface
            font.pixelSize: 12
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        id: area

        property real dragValue: 0
        readonly property real hoverValue: Math.max(0, Math.min(1, mouseX / Math.max(1, width)))

        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        function take(x) {
            dragValue = Math.max(0, Math.min(1, x / Math.max(1, width)))
            root.moved(dragValue)
        }

        onPressed: (mouse) => take(mouse.x)
        onPositionChanged: (mouse) => {
            if (pressed)
                take(mouse.x)
        }
    }
}
