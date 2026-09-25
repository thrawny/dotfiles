{
  # super+r opens the team's PR review queue. bin/pr-review reads the team from
  # the private work config, which only this machine has.
  dotfiles.herdr.extraPlugins = [ "pr-review" ];

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
