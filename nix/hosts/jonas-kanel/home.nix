{ pkgs, lib, ... }:
{
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "terraform"
    ];

  home.packages = with pkgs; [
    terraform
    tflint
    go-migrate
    upx
  ];
}
