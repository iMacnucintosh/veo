import QtQuick

// Material 3 expressive effects motion (opacity, colour-free values) at the shell's speed: no overshoot.
NumberAnimation {
    property bool fast: false

    duration: Theme.ms(fast ? 150 : 200)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: fast ? [0.31, 0.94, 0.34, 1, 1, 1] : [0.34, 0.8, 0.34, 1, 1, 1]
}
