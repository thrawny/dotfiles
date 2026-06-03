_: {
  programs.lazygit = {
    enable = true;
    settings = {
      promptToReturnFromSubprocess = false;
      quitOnTopLevelReturn = true;

      git.pagers = [
        {
          colorArg = "always";
          pager = "delta --dark --paging=never --syntax-theme='Monokai Extended' --line-numbers --plus-style='syntax \"#004466\"' --plus-emph-style='syntax \"#0077b3\"' --plus-non-emph-style='syntax \"#003355\"' --minus-style='syntax \"#660100\"' --minus-emph-style='syntax \"#b30100\"' --minus-non-emph-style='syntax \"#440100\"' --line-numbers-minus-style='#ff6666' --line-numbers-plus-style='#66aaff' --line-numbers-zero-style='#888888'";
        }
        {
          externalDiffCommand = "difft --color=always --display=inline";
        }
      ];

      os = {
        edit = ''[ -z "$NVIM" ] && nvim {{filename}} || (nvim --server "$NVIM" --remote-send "q" && nvim --server "$NVIM" --remote {{filename}})'';
        editAtLine = ''[ -z "$NVIM" ] && nvim +{{line}} {{filename}} || (nvim --server "$NVIM" --remote-send "q" && nvim --server "$NVIM" --remote +{{line}} {{filename}})'';
      };
    };
  };
}
