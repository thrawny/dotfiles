# Hermes 0.21.0 imports these modules but omits them from setuptools.py-modules.
# Supply only the missing files from the same locked source, through upstream's
# extraPythonPackages hook. Remove this workaround once upstream packages both.
{
  lib,
  pkgs,
  source,
}:
let
  declared =
    (builtins.fromTOML (builtins.readFile "${source}/pyproject.toml")).tool.setuptools.py-modules;
  missing = builtins.filter (name: !(builtins.elem name declared)) [
    "hermes_state_holders"
    "hermes_state_registry"
  ];
in
pkgs.python312.pkgs.toPythonModule (
  pkgs.runCommand "hermes-missing-state-modules" { } ''
    mkdir -p "$out/${pkgs.python312.sitePackages}"
    ${lib.concatMapStringsSep "\n" (name: ''
      cp ${source}/${name}.py "$out/${pkgs.python312.sitePackages}/${name}.py"
    '') missing}
  ''
)
