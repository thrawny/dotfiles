{ pkgs }:
let
  inherit (pkgs) lib;
  themeLib = import ./theme.nix { inherit lib; };
  theme = themeLib.loadTheme ../themes/monokai.json;
  s = theme.semantic;
  # T3 Code derives its palette from canvas and accent; colors pins the rest.
  t3codeTheme = pkgs.writeText "t3code-theme-monokai.json" (
    builtins.toJSON {
      version = 1;
      name = "Monokai";
      appearance = "dark";
      canvas = s.background;
      inherit (s) accent;
      colors = {
        inherit (s)
          surface
          border
          error
          warning
          ;
        text = s.foreground;
        textMuted = s.muted;
        placeholder = s.dim;
        iconMuted = s.dim;
        focus = s.accentAlt;
        codeBackground = theme.terminal.background;
        codeForeground = s.foreground;
        searchMatchBackground = s.selection;
        searchMatchForeground = s.foreground;
        searchMatchActiveBackground = theme.syntax.string;
        searchMatchActiveForeground = s.background;
        sidebarRowSelected = s.selection;
        terminalBackground = theme.terminal.background;
        terminalForeground = theme.terminal.foreground;
        terminalCursor = theme.applications.ghostty.cursor;
        terminalSelection = theme.terminal.selection;
      };
    }
  );
in
pkgs.writeShellApplication {
  name = "t3code-preferences";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
  ];
  text = ''
    export T3CODE_THEME=${t3codeTheme}
  ''
  + builtins.readFile ../../scripts/t3code-preferences;
}
