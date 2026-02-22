_: {
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      format = "$username$hostname$directory$git_branch$git_state$git_status$git_metrics$env_var$kubernetes$docker_context$python$golang$nodejs$rust$terraform$cmd_duration$line_break$character";

      git_status.stashed = "";
      git_branch.symbol = "";
      cmd_duration.min_time = 500;

      kubernetes = {
        disabled = false;
        format = "on [$symbol$context]($style) ";
      };

      env_var.DEVPOD = {
        format = "in [📦 devpod]($style) ";
        style = "bold blue";
      };

      env_var.ZMX_SESSION = {
        format = "in [🛸 zmx:$env_value]($style) ";
        style = "bold cyan";
      };
    };
  };
}
