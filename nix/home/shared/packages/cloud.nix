{
  pkgs,
  ...
}:
let
  kubectl134 =
    if pkgs.stdenv.isLinux && pkgs.stdenv.hostPlatform.isx86_64 then
      pkgs.stdenvNoCC.mkDerivation {
        pname = "kubectl";
        version = "1.34.5";
        src = pkgs.fetchurl {
          url = "https://dl.k8s.io/release/v1.34.5/bin/linux/amd64/kubectl";
          hash = "sha256-ahfdg4d4OzFEplU1440Cw1ECfpcY6jSmw2BHbLJtKLs=";
        };
        dontUnpack = true;
        installPhase = ''
          install -Dm755 "$src" "$out/bin/kubectl"
        '';
      }
    else
      pkgs.kubectl;
in
{
  home.packages = with pkgs; [
    k9s
    awscli2
    kubectl134
    kind
    kustomize
    kubernetes-helm
  ];
}
