_: {
  xdg.desktopEntries.btop = {
    name = "btop++";
    comment = "Resource monitor that shows usage and stats for processor, memory, disks, network and processes";
    exec = "ghostty --class=btop -e btop";
    icon = "btop";
    terminal = false;
    type = "Application";
    categories = [
      "System"
      "Monitor"
    ];
  };
}
