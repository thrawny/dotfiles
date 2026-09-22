// Shared navigation for all shell pickers. Zero leaves the key to the input.
function direction(key, modifiers) {
    const control = modifiers & Qt.ControlModifier;
    if (key === Qt.Key_Up || (control && (key === Qt.Key_K || key === Qt.Key_P)))
        return -1;
    if (key === Qt.Key_Down || (control && (key === Qt.Key_J || key === Qt.Key_N)))
        return 1;
    return 0;
}
