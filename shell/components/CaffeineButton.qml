import QtQuick
import "../services"

BarButton {
    id: root
    text: Caffeine.active ? "󰅶" : "󰛊"
    selected: Caffeine.active
    attention: Caffeine.error !== "" || Caffeine.actionError !== ""
    hint: Caffeine.tooltip
    onClicked: {
        if (details.visible)
            details.close();
        else {
            details.open();
            Caffeine.refresh();
        }
    }
    onSecondaryClicked: Caffeine.toggle()
    CaffeineDetails {
        id: details
        x: root.width - width
        y: root.height + 6
    }
}
