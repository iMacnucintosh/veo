import QtQuick

// Material 3 expressive effects motion for colours, at the shell's speed
ColorAnimation {
    duration: Theme.ms(200)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1]
}
