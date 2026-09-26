let
  stdlib = builtins.readFile ./direnv-stdlib.sh;
in
{
  inherit stdlib;

  rcFor =
    pkgs:
    pkgs.writeText "dotfiles-direnvrc" ''
      source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc
      ${stdlib}
    '';
}
