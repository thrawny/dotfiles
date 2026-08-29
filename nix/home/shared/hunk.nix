{ hunk, theme, ... }:
let
  inherit (theme) diff;
  sem = theme.semantic;
  syn = theme.syntax;
  app = theme.applications.hunk;
in
{
  imports = [ hunk.homeManagerModules.default ];

  programs.hunk = {
    enable = true;
    enableGitIntegration = false;
    settings = {
      theme = "custom";
      mode = "auto";
      line_numbers = true;
      wrap_lines = false;
      agent_notes = true;
      transparent_background = false;

      custom_theme = {
        base = "graphite";
        label = "Monokai Spectrum";
        inherit (sem) background border;
        inherit (app) panelAlt accentMuted muted;
        panel = sem.background;
        accent = diff.changed.foreground;
        text = sem.foreground;
        addedBg = diff.added.lineBackground;
        removedBg = diff.removed.lineBackground;
        movedAddedBg = diff.added.dimBackground;
        movedRemovedBg = diff.removed.dimBackground;
        contextBg = sem.background;
        addedContentBg = diff.added.emphasisBackground;
        removedContentBg = diff.removed.emphasisBackground;
        contextContentBg = sem.background;
        addedSignColor = diff.added.foreground;
        removedSignColor = diff.removed.foreground;
        lineNumberBg = sem.background;
        lineNumberFg = app.muted;
        inherit (app) selectedHunk noteBackground noteTitleBackground;
        badgeAdded = diff.added.foreground;
        badgeRemoved = diff.removed.foreground;
        badgeNeutral = diff.changed.foreground;
        fileNew = diff.added.foreground;
        fileDeleted = diff.removed.foreground;
        fileRenamed = diff.changed.foreground;
        fileModified = sem.accentAlt;
        fileUntracked = sem.warning;
        noteBorder = sem.accentAlt;
        noteTitleText = sem.foreground;

        syntax = {
          inherit (syn)
            keyword
            string
            comment
            number
            type
            ;
          inherit (app) punctuation;
          default = syn.variable;
          function = syn."function";
          property = syn.number;
        };
      };
    };
  };
}
