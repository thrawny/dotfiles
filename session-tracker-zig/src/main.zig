const std = @import("std");
const json = std.json;
const fs = std.fs;
const posix = std.posix;

const SessionData = struct {
    session_id: []const u8,
    transcript_path: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    niri_window_id: ?[]const u8 = null,
    tmux_window_id: ?[]const u8 = null,
    state: []const u8,
    state_updated: f64,
};

const Sessions = std.StringHashMap(SessionData);

fn getHomeDir() ?[]const u8 {
    return posix.getenv("HOME");
}

fn sessionsFilePath(allocator: std.mem.Allocator) ![]const u8 {
    const home = getHomeDir() orelse return error.NoHomeDir;
    return std.fmt.allocPrint(allocator, "{s}/.claude/active-sessions.json", .{home});
}

fn loadSessions(allocator: std.mem.Allocator) !Sessions {
    var sessions = Sessions.init(allocator);

    const path = sessionsFilePath(allocator) catch return sessions;
    defer allocator.free(path);

    const file = fs.openFileAbsolute(path, .{}) catch return sessions;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch return sessions;
    defer allocator.free(content);

    const parsed = json.parseFromSlice(json.Value, allocator, content, .{}) catch return sessions;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return sessions;

    var iter = root.object.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;

        if (val != .object) continue;

        const obj = val.object;
        const session_id = if (obj.get("session_id")) |v| (if (v == .string) v.string else null) else null;
        const state = if (obj.get("state")) |v| (if (v == .string) v.string else null) else null;
        const state_updated = if (obj.get("state_updated")) |v| (if (v == .float) v.float else if (v == .integer) @as(f64, @floatFromInt(v.integer)) else null) else null;

        if (session_id == null or state == null or state_updated == null) continue;

        const key_copy = allocator.dupe(u8, key) catch continue;

        sessions.put(key_copy, .{
            .session_id = allocator.dupe(u8, session_id.?) catch continue,
            .transcript_path = if (obj.get("transcript_path")) |v| (if (v == .string) allocator.dupe(u8, v.string) catch null else null) else null,
            .cwd = if (obj.get("cwd")) |v| (if (v == .string) allocator.dupe(u8, v.string) catch null else null) else null,
            .niri_window_id = if (obj.get("niri_window_id")) |v| (if (v == .string) allocator.dupe(u8, v.string) catch null else null) else null,
            .tmux_window_id = if (obj.get("tmux_window_id")) |v| (if (v == .string) allocator.dupe(u8, v.string) catch null else null) else null,
            .state = allocator.dupe(u8, state.?) catch continue,
            .state_updated = state_updated.?,
        }) catch continue;
    }

    return sessions;
}

fn saveSessions(allocator: std.mem.Allocator, sessions: *Sessions) !void {
    const path = try sessionsFilePath(allocator);
    defer allocator.free(path);

    // Ensure parent directory exists
    const home = getHomeDir() orelse return error.NoHomeDir;
    const claude_dir = try std.fmt.allocPrint(allocator, "{s}/.claude", .{home});
    defer allocator.free(claude_dir);
    fs.makeDirAbsolute(claude_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    try output.appendSlice(allocator, "{\n");

    var first = true;
    var iter = sessions.iterator();
    while (iter.next()) |entry| {
        if (!first) try output.appendSlice(allocator, ",\n");
        first = false;

        const key = entry.key_ptr.*;
        const data = entry.value_ptr.*;

        try std.fmt.format(output.writer(allocator), "  \"{s}\": {{\n", .{key});
        try std.fmt.format(output.writer(allocator), "    \"session_id\": \"{s}\",\n", .{data.session_id});

        if (data.transcript_path) |tp| {
            try std.fmt.format(output.writer(allocator), "    \"transcript_path\": \"{s}\",\n", .{tp});
        } else {
            try output.appendSlice(allocator, "    \"transcript_path\": null,\n");
        }

        if (data.cwd) |c| {
            try std.fmt.format(output.writer(allocator), "    \"cwd\": \"{s}\",\n", .{c});
        } else {
            try output.appendSlice(allocator, "    \"cwd\": null,\n");
        }

        if (data.niri_window_id) |n| {
            try std.fmt.format(output.writer(allocator), "    \"niri_window_id\": \"{s}\",\n", .{n});
        } else {
            try output.appendSlice(allocator, "    \"niri_window_id\": null,\n");
        }

        if (data.tmux_window_id) |t| {
            try std.fmt.format(output.writer(allocator), "    \"tmux_window_id\": \"{s}\",\n", .{t});
        } else {
            try output.appendSlice(allocator, "    \"tmux_window_id\": null,\n");
        }

        try std.fmt.format(output.writer(allocator), "    \"state\": \"{s}\",\n", .{data.state});
        try std.fmt.format(output.writer(allocator), "    \"state_updated\": {d}\n", .{data.state_updated});
        try output.appendSlice(allocator, "  }");
    }

    try output.appendSlice(allocator, "\n}\n");

    const file = try fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll(output.items);
}

fn now() f64 {
    const ts = std.time.timestamp();
    const ns = std.time.nanoTimestamp();
    const fractional = @as(f64, @floatFromInt(@mod(ns, std.time.ns_per_s))) / @as(f64, std.time.ns_per_s);
    return @as(f64, @floatFromInt(ts)) + fractional;
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout = child.stdout orelse return error.NoStdout;
    const output = try stdout.readToEndAlloc(allocator, 64 * 1024);

    const term = try child.wait();
    if (term.Exited != 0) {
        allocator.free(output);
        return error.CommandFailed;
    }

    return output;
}

fn getNiriWindowId(allocator: std.mem.Allocator) ?[]const u8 {
    const output = runCommand(allocator, &.{ "niri", "msg", "-j", "focused-window" }) catch return null;
    defer allocator.free(output);

    const parsed = json.parseFromSlice(json.Value, allocator, output, .{}) catch return null;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return null;

    const title = if (root.object.get("title")) |v| (if (v == .string) v.string else null) else null;
    if (title == null) return null;

    // Only register if title starts with Claude's marker (UTF-8 encoded)
    if (title.?.len > 0 and (std.mem.startsWith(u8, title.?, "\xe2\x9c\xb3") or std.mem.startsWith(u8, title.?, "\xe2\x9c\xb6"))) {
        const id = root.object.get("id") orelse return null;
        if (id == .integer) {
            return std.fmt.allocPrint(allocator, "{d}", .{id.integer}) catch null;
        }
    }

    return null;
}

fn getTmuxWindowId(allocator: std.mem.Allocator) ?[]const u8 {
    if (posix.getenv("TMUX") == null) return null;

    const output = runCommand(allocator, &.{ "tmux", "display-message", "-p", "#{window_id}" }) catch return null;

    const trimmed = std.mem.trim(u8, output, " \t\n\r");
    if (trimmed.len == 0) {
        allocator.free(output);
        return null;
    }

    // Return a copy of just the trimmed portion
    const result = allocator.dupe(u8, trimmed) catch {
        allocator.free(output);
        return null;
    };
    allocator.free(output);
    return result;
}

fn getWindowId(allocator: std.mem.Allocator) ?[]const u8 {
    return getNiriWindowId(allocator) orelse getTmuxWindowId(allocator);
}

fn findSessionBySessionId(sessions: *Sessions, session_id: []const u8) ?[]const u8 {
    var iter = sessions.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.*.session_id, session_id)) {
            return entry.key_ptr.*;
        }
    }
    return null;
}

fn endsWithQuestion(allocator: std.mem.Allocator, transcript_path: []const u8) bool {
    const output = runCommand(allocator, &.{ "tail", "-n", "20", transcript_path }) catch return false;
    defer allocator.free(output);

    var last_text: ?[]const u8 = null;
    var last_text_buf: ?[]u8 = null;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        const parsed = json.parseFromSlice(json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) continue;

        const entry_type = if (root.object.get("type")) |v| (if (v == .string) v.string else null) else null;
        if (entry_type == null or !std.mem.eql(u8, entry_type.?, "assistant")) continue;

        const message = root.object.get("message") orelse continue;
        if (message != .object) continue;

        const content = message.object.get("content") orelse continue;
        if (content != .array) continue;

        for (content.array.items) |item| {
            if (item != .object) continue;
            const item_type = if (item.object.get("type")) |v| (if (v == .string) v.string else null) else null;
            if (item_type == null or !std.mem.eql(u8, item_type.?, "text")) continue;

            const text = if (item.object.get("text")) |v| (if (v == .string) v.string else null) else null;
            if (text) |t| {
                if (last_text_buf) |buf| allocator.free(buf);
                last_text_buf = allocator.dupe(u8, t) catch null;
                last_text = last_text_buf;
            }
        }
    }

    defer if (last_text_buf) |buf| allocator.free(buf);

    if (last_text) |text| {
        const trimmed = std.mem.trimRight(u8, text, " \t\n\r");
        return trimmed.len > 0 and trimmed[trimmed.len - 1] == '?';
    }

    return false;
}

fn readStdin(allocator: std.mem.Allocator) ![]u8 {
    const stdin_file = fs.File.stdin();
    return stdin_file.readToEndAlloc(allocator, 1024 * 1024);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read stdin
    const input = readStdin(allocator) catch return;
    defer allocator.free(input);

    // Parse hook input
    const parsed = json.parseFromSlice(json.Value, allocator, input, .{}) catch return;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return;

    const event = if (root.object.get("hook_event_name")) |v| (if (v == .string) v.string else null) else null;
    const session_id = if (root.object.get("session_id")) |v| (if (v == .string) v.string else null) else null;
    const transcript_path = if (root.object.get("transcript_path")) |v| (if (v == .string) v.string else null) else null;
    const cwd = if (root.object.get("cwd")) |v| (if (v == .string) v.string else null) else null;
    const notification_type = if (root.object.get("notification_type")) |v| (if (v == .string) v.string else null) else null;

    if (session_id == null) return;

    var sessions = try loadSessions(allocator);
    defer {
        var iter = sessions.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*.session_id);
            if (entry.value_ptr.*.transcript_path) |tp| allocator.free(tp);
            if (entry.value_ptr.*.cwd) |c| allocator.free(c);
            if (entry.value_ptr.*.niri_window_id) |n| allocator.free(n);
            if (entry.value_ptr.*.tmux_window_id) |t| allocator.free(t);
            allocator.free(entry.value_ptr.*.state);
        }
        sessions.deinit();
    }

    if (event == null) return;

    if (std.mem.eql(u8, event.?, "SessionStart")) {
        const niri_id = getNiriWindowId(allocator);
        const tmux_id = getTmuxWindowId(allocator);
        const window_id = niri_id orelse tmux_id;

        if (window_id) |wid| {
            // Remove old entry if exists
            if (sessions.fetchRemove(wid)) |old| {
                allocator.free(old.key);
                allocator.free(old.value.session_id);
                if (old.value.transcript_path) |tp| allocator.free(tp);
                if (old.value.cwd) |c| allocator.free(c);
                if (old.value.niri_window_id) |n| allocator.free(n);
                if (old.value.tmux_window_id) |t| allocator.free(t);
                allocator.free(old.value.state);
            }

            const key = try allocator.dupe(u8, wid);
            try sessions.put(key, .{
                .session_id = try allocator.dupe(u8, session_id.?),
                .transcript_path = if (transcript_path) |tp| try allocator.dupe(u8, tp) else null,
                .cwd = if (cwd) |c| try allocator.dupe(u8, c) else null,
                .niri_window_id = if (niri_id) |n| try allocator.dupe(u8, n) else null,
                .tmux_window_id = if (tmux_id) |t| try allocator.dupe(u8, t) else null,
                .state = try allocator.dupe(u8, "waiting"),
                .state_updated = now(),
            });
            try saveSessions(allocator, &sessions);

            // Free the window IDs we got since we made copies
            if (niri_id) |n| allocator.free(n);
            if (tmux_id) |t| allocator.free(t);
        } else {
            if (niri_id) |n| allocator.free(n);
            if (tmux_id) |t| allocator.free(t);
        }
    } else if (std.mem.eql(u8, event.?, "SessionEnd")) {
        const window_id = getWindowId(allocator) orelse findSessionBySessionId(&sessions, session_id.?);

        if (window_id) |wid| {
            const should_free = (getWindowId(allocator) != null);
            if (sessions.fetchRemove(wid)) |old| {
                allocator.free(old.key);
                allocator.free(old.value.session_id);
                if (old.value.transcript_path) |tp| allocator.free(tp);
                if (old.value.cwd) |c| allocator.free(c);
                if (old.value.niri_window_id) |n| allocator.free(n);
                if (old.value.tmux_window_id) |t| allocator.free(t);
                allocator.free(old.value.state);
                try saveSessions(allocator, &sessions);
            }
            if (should_free) allocator.free(wid);
        }
    } else if (std.mem.eql(u8, event.?, "Stop")) {
        const window_id = findSessionBySessionId(&sessions, session_id.?);

        if (window_id) |wid| {
            if (sessions.getPtr(wid)) |session| {
                const is_question = if (session.transcript_path) |tp| endsWithQuestion(allocator, tp) else false;

                allocator.free(session.state);
                session.state = try allocator.dupe(u8, if (is_question) "waiting" else "idle");
                session.state_updated = now();
                try saveSessions(allocator, &sessions);
            }
        }
    } else if (std.mem.eql(u8, event.?, "Notification")) {
        if (notification_type != null and std.mem.eql(u8, notification_type.?, "permission_prompt")) {
            const window_id = findSessionBySessionId(&sessions, session_id.?);

            if (window_id) |wid| {
                if (sessions.getPtr(wid)) |session| {
                    allocator.free(session.state);
                    session.state = try allocator.dupe(u8, "waiting");
                    session.state_updated = now();
                    try saveSessions(allocator, &sessions);
                }
            }
        }
    } else if (std.mem.eql(u8, event.?, "UserPromptSubmit")) {
        const window_id = findSessionBySessionId(&sessions, session_id.?);

        if (window_id) |wid| {
            if (sessions.getPtr(wid)) |session| {
                allocator.free(session.state);
                session.state = try allocator.dupe(u8, "responding");
                session.state_updated = now();
                try saveSessions(allocator, &sessions);
            }
        } else {
            // Session not registered yet (e.g., resumed session)
            const niri_id = getNiriWindowId(allocator);
            const tmux_id = getTmuxWindowId(allocator);
            const new_window_id = niri_id orelse tmux_id;

            if (new_window_id) |new_wid| {
                const key = try allocator.dupe(u8, new_wid);
                try sessions.put(key, .{
                    .session_id = try allocator.dupe(u8, session_id.?),
                    .transcript_path = if (transcript_path) |tp| try allocator.dupe(u8, tp) else null,
                    .cwd = if (cwd) |c| try allocator.dupe(u8, c) else null,
                    .niri_window_id = if (niri_id) |n| try allocator.dupe(u8, n) else null,
                    .tmux_window_id = if (tmux_id) |t| try allocator.dupe(u8, t) else null,
                    .state = try allocator.dupe(u8, "responding"),
                    .state_updated = now(),
                });
                try saveSessions(allocator, &sessions);

                if (niri_id) |n| allocator.free(n);
                if (tmux_id) |t| allocator.free(t);
            } else {
                if (niri_id) |n| allocator.free(n);
                if (tmux_id) |t| allocator.free(t);
            }
        }
    } else if (std.mem.eql(u8, event.?, "PreToolUse")) {
        const window_id = findSessionBySessionId(&sessions, session_id.?);

        if (window_id) |wid| {
            if (sessions.getPtr(wid)) |session| {
                if (std.mem.eql(u8, session.state, "waiting")) {
                    allocator.free(session.state);
                    session.state = try allocator.dupe(u8, "responding");
                    session.state_updated = now();
                    try saveSessions(allocator, &sessions);
                }
            }
        }
    }
}
