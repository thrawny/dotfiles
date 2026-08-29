{ theme, themeLib, ... }:
{
  programs.lazygit = {
    enable = true;
    settings = {
      promptToReturnFromSubprocess = false;
      quitOnTopLevelReturn = true;

      git.diffRenderers = [
        {
          colorArg = "always";
          command = "delta --paging=never ${themeLib.deltaArgs theme}";
        }
        {
          command = "difft --color=always --display=inline";
          type = "extDiff";
        }
      ];

      os = {
        edit = ''[ -z "$NVIM" ] && nvim {{filename}} || (nvim --server "$NVIM" --remote-send "q" && nvim --server "$NVIM" --remote {{filename}})'';
        editAtLine = ''[ -z "$NVIM" ] && nvim +{{line}} {{filename}} || (nvim --server "$NVIM" --remote-send "q" && nvim --server "$NVIM" --remote +{{line}} {{filename}})'';
      };
    };
  };
}
