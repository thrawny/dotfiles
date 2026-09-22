// Shared by the bar model and its tests. Keep aligned with binds.lua.
function ordered(workspaces) {
    return workspaces.filter(ws => !ws.name.startsWith("special:"))
        .slice().sort((a, b) => a.id - b.id);
}

function shortcut(index) {
    return index < 10 ? String((index + 1) % 10) : "";
}

function focusRequest(id) {
    if (!Number.isSafeInteger(id)) throw new Error("Invalid workspace ID");
    return 'hl.dsp.focus({workspace = "' + id + '"})';
}
