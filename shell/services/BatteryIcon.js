// Nerd Font Material Design battery levels, empty through full.
function icon(fraction) {
    if (!Number.isFinite(fraction)) return "󰂑";
    const levels = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"];
    const level = Math.floor(Math.max(0, Math.min(1, fraction)) * 10);
    return levels[level];
}
