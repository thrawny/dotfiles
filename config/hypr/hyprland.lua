-- Hyprland Lua config (0.56+, hyprlang is deprecated).
-- Symlinked from dotfiles/config/hypr via home-manager (mutable):
-- edit here, then `hyprctl reload` — no `just switch` needed.

local confdir = os.getenv("HOME") .. "/.config/hypr"
package.path = confdir .. "/lua/?.lua;" .. package.path

require("options")
require("rules")
require("projectdirs")
require("binds")
require("appjump")
require("autostart")

-- Optional host-local overrides (gitignored), mirrors niri's local.kdl.
pcall(require, "host")
