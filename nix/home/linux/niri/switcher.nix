# Agent switcher (Rust GTK4 app)
# Assumes agent-switch is available on PATH (e.g., ~/.cargo/bin)
_: {
  programs.niri.settings = {
    spawn-at-startup = [
      {
        command = [
          "agent-switch"
          "niri"
        ];
      }
    ];

    binds = {
      "Mod+S" = {
        action.spawn = [
          "agent-switch"
          "niri"
          "--toggle"
        ];
        hotkey-overlay.title = "Agent Switcher";
      };
    };
  };
}
