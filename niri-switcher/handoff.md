# Handoff: Fix Lint Errors

## Next Goal
Fix the 4 dead code warnings in niri-switcher.

## Context
The niri-switcher is a GTK4 project switcher for niri that shows Claude session states (working/waiting/idle). It's fully functional but has dead code warnings from earlier refactoring.

## Current Warnings
```
warning: field `window_id` is never read
  --> src/main.rs:64:22
   ClaudeActivity { window_id: u64 },

warning: field `key` is never read
  --> src/main.rs:90:5
   key: String,  (in struct Project)

warning: function `workspace_has_windows` is never used
   --> src/main.rs:167:4

warning: function `switch_to_project` is never used
   --> src/main.rs:350:4
```

## Analysis
- `ClaudeActivity { window_id }` - The variant is used at line 590 and matched at line 875 but `window_id` field is ignored with `_`
- `Project.key` - Field from config parsing but never used (we use workspace index instead)
- `workspace_has_windows` - Called only by `switch_to_project`
- `switch_to_project` - Old function, replaced by `switch_to_entry`

## Files
- `niri-switcher/src/main.rs:60-70` - Message enum with ClaudeActivity
- `niri-switcher/src/main.rs:88-95` - Project struct
- `niri-switcher/src/main.rs:167-185` - workspace_has_windows function
- `niri-switcher/src/main.rs:350-365` - switch_to_project function

## Immediate Action
1. Remove `window_id` field from `ClaudeActivity` variant (change to unit variant or remove entirely if not needed)
2. Add `#[allow(dead_code)]` to `Project.key` field OR remove it if config doesn't need it
3. Remove `workspace_has_windows` and `switch_to_project` functions (they're unused)
4. Build with `mise run build` to verify fixes

## Build Command
```bash
cd niri-switcher && mise run build
```
