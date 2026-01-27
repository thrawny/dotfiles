{
  username,
  ...
}:
{
  imports = [
    # Only shared cross-platform modules (no Wayland/UI)
    ../shared
  ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";
  };
}
