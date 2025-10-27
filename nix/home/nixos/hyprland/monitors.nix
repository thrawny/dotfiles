_:
{
  wayland.windowManager.hyprland.settings = {
    # Monitor configuration
    monitor = [
      "HDMI-A-1,2560x1440@144,0x0,1"
      "DP-1,2560x1440@144,2560x0,1"
      ",preferred,auto,1" # Fallback for other monitors
    ];

    # Workspace to monitor assignments
    # Mirrors aerospace config pattern:
    # - Workspaces 1, 3, 4 on primary (left) monitor
    # - Workspace 2 on secondary (right) monitor
    # - Named workspaces (b=browser on right, p=player on left)
    workspace = [
      "1, monitor:HDMI-A-1, default:true"
      "2, monitor:HDMI-A-1"
      "3, monitor:HDMI-A-1"
      "4, monitor:HDMI-A-1"
      "name:b, monitor:DP-1" # Browser workspace
      "name:p, monitor:HDMI-A-1" # Spotify workspace
    ];
  };
}
