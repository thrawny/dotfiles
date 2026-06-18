{ hunk, ... }:
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
        background = "#222222";
        panel = "#222222";
        panelAlt = "#252525";
        border = "#5f5b63";
        accent = "#fce566";
        accentMuted = "#34313a";
        text = "#f7f1ff";
        muted = "#78747d";
        addedBg = "#004466";
        removedBg = "#660100";
        movedAddedBg = "#003355";
        movedRemovedBg = "#440100";
        contextBg = "#222222";
        addedContentBg = "#0077b3";
        removedContentBg = "#b30100";
        contextContentBg = "#222222";
        addedSignColor = "#5ad4e6";
        removedSignColor = "#ff6666";
        lineNumberBg = "#222222";
        lineNumberFg = "#78747d";
        selectedHunk = "#004b8f";
        badgeAdded = "#5ad4e6";
        badgeRemoved = "#ff6666";
        badgeNeutral = "#fce566";
        fileNew = "#5ad4e6";
        fileDeleted = "#ff6666";
        fileRenamed = "#fce566";
        fileModified = "#948ae3";
        fileUntracked = "#fc9867";
        noteBorder = "#948ae3";
        noteBackground = "#2b2435";
        noteTitleBackground = "#3a2d4a";
        noteTitleText = "#f7f1ff";

        syntax = {
          default = "#f7f1ff";
          keyword = "#fc618d";
          string = "#fce566";
          comment = "#8b888f";
          number = "#948ae3";
          function = "#fce566";
          property = "#948ae3";
          type = "#5ad4e6";
          punctuation = "#c8c3cf";
        };
      };
    };
  };
}
