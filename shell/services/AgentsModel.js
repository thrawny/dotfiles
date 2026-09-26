function rows(threads, area, globalScope, settled, archived) {
    const inScope = threads.filter(thread => globalScope || !area || thread.area === area);
    const order = {active: 0, settled: 1, archived: 2};
    return inScope.filter(thread => thread.lifecycle === "active" || (thread.lifecycle === "settled" && settled) || (thread.lifecycle === "archived" && archived)).sort((a, b) => order[a.lifecycle] - order[b.lifecycle] || (a.lifecycle === "active" ? b.order - a.order : (b.settled_at || 0) - (a.settled_at || 0)) || b.seq - a.seq);
}

function counts(threads) {
    const result = {active: 0, settled: 0, archived: 0, working: 0, done: 0, approval: 0, input: 0, idle: 0};
    threads.forEach(thread => {
        if (result[thread.lifecycle] !== undefined)
            result[thread.lifecycle]++;
        if (thread.lifecycle === "active" && result[thread.attention] !== undefined)
            result[thread.attention]++;
    });
    return result;
}

function validate(snapshot) {
    const states = ["idle", "working", "done", "input", "approval"];
    const shelves = ["active", "settled", "archived"];
    if (!snapshot || snapshot.schema_version !== 1 || !Array.isArray(snapshot.threads) || !Number.isFinite(snapshot.updated_at))
        throw new Error("Unsupported agent-switch snapshot");
    if (snapshot.focused_area !== null && typeof snapshot.focused_area !== "string")
        throw new Error("Invalid focused area");
    if (snapshot.message !== undefined && snapshot.message !== null && typeof snapshot.message !== "string")
        throw new Error("Invalid agent-switch message");
    const seen = new Set();
    if (!snapshot.threads.every(thread => {
        if (!thread || !Number.isSafeInteger(thread.seq) || thread.seq < 0 || seen.has(thread.seq) || !Number.isSafeInteger(thread.order) || thread.order < 0)
            return false;
        seen.add(thread.seq);
        return ["title", "harness", "area", "repo", "branch"].every(field => typeof thread[field] === "string")
            && typeof thread.cold === "boolean" && typeof thread.parked === "boolean"
            && Number.isFinite(thread.state_updated)
            && (thread.settled_at === null || Number.isFinite(thread.settled_at))
            && states.includes(thread.attention) && shelves.includes(thread.lifecycle);
    }))
        throw new Error("Invalid agent-switch thread");
    return snapshot;
}

function age(timestamp, now) {
    const seconds = Math.max(0, Math.floor(now - timestamp));
    if (seconds < 60)
        return seconds + "s";
    if (seconds < 3600)
        return Math.floor(seconds / 60) + "m";
    return Math.floor(seconds / 3600) + "h";
}

// Headers are presentation rows only. Thread jump indexes still refer to the
// service's visible threads, so opening a shelf cannot steal a keyboard slot.
function displayRows(threads, counts, settledExpanded, archivedExpanded) {
    const display = [];
    for (const lifecycle of ["active", "settled", "archived"]) {
        if (lifecycle !== "active" && counts[lifecycle] > 0)
            display.push({kind: "shelf", lifecycle: lifecycle, count: counts[lifecycle], expanded: lifecycle === "settled" ? settledExpanded : archivedExpanded});
        threads.forEach((thread, index) => {
            if (thread.lifecycle === lifecycle)
                display.push({kind: "thread", thread: thread, jumpIndex: index + 1});
        });
    }
    return display;
}

function locationText(thread, globalScope) {
    if (globalScope && thread.area && thread.area !== thread.repo)
        return [thread.area, thread.repo].filter(Boolean).join(" · ");
    return thread.repo || thread.area;
}

function relativeTime(timestamp, now) {
    const minutes = Math.max(0, Math.floor((now - timestamp) / 60));
    if (minutes === 0)
        return "now";
    if (minutes < 60)
        return minutes + "m";
    if (minutes < 1440)
        return Math.floor(minutes / 60) + "h";
    return Math.floor(minutes / 1440) + "d";
}

function statusLabel(thread, now) {
    if (thread.lifecycle !== "active")
        return relativeTime(thread.settled_at ?? thread.state_updated, now);
    if (thread.attention === "approval")
        return "Approval";
    if (thread.attention === "input")
        return "Input";
    if (thread.attention === "done")
        return "✓ Done";
    if (thread.attention === "working") {
        const seconds = Math.max(0, Math.floor(now - thread.state_updated));
        const duration = seconds < 60 ? seconds + "s" : seconds < 3600 ? Math.floor(seconds / 60) + "m" : Math.floor(seconds / 3600) + "h " + Math.floor(seconds % 3600 / 60) + "m";
        return "Working " + duration;
    }
    return relativeTime(thread.state_updated, now);
}
