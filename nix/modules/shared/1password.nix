{ config, ... }:
{
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ config.dotfiles.username ];
  };

  # Allow Zen Browser to use 1Password browser extension
  environment.etc."1password/custom_allowed_browsers" = {
    text = ''
      .zen-wrapped
    '';
    mode = "0755";
  };
}
