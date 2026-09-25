{
  # super+r opens the team's PR review queue. The picker lives in the es-utils
  # repo under ~/code, which only this machine has, and Herdr keybindings can
  # only be declared in config.toml. Binding by plugin id keeps that repo's
  # name and layout out of the shared config; if the plugin is not linked, the
  # key does nothing.
  dotfiles.herdr.commands = [
    {
      key = "super+r";
      type = "plugin_action";
      command = "thrawny.pr-review.open";
      description = "Review a pull request";
    }
  ];

  # Claude is the only agent here, so the agent name on every row says nothing.
  dotfiles.herdr.showAgentName = false;
}
