{
  lazy-nvim-nix,
  nvim-auto-save,
  nvim-baml-syntax,
  nvim-codediff,
  nvim-git-conflict,
  nvim-monokai-pro,
  nvim-tmux-navigator,
  pkgs,
}:
let
  lazyNvim = (pkgs.extend lazy-nvim-nix.overlays.default).lazy-nvim-nix;
  # Mason is disabled and editor tools already live in the shared Home Manager
  # package sets. Avoid pulling every tool supported by LazyVim into this
  # package's closure while retaining lazy-nvim-nix's plugin-specific specs.
  pluginsWithoutBundledTools = pkgs.lib.mapAttrs (
    _name: plugin:
    plugin
    // pkgs.lib.optionalAttrs (plugin ? extraPackages) {
      extraPackages = [ ];
    }
  ) lazyNvim.plugins;
  leanLazyNvim = lazyNvim // {
    plugins = pluginsWithoutBundledTools;
  };
  themeLib = import ./theme.nix { inherit (pkgs) lib; };
  themeJson = pkgs.writeText "dotfiles-theme.json" (
    builtins.toJSON (themeLib.loadTheme ../themes/monokai.json)
  );
  nvimRoot = ../../config/nvim;
  nvimConfig = pkgs.lib.fileset.toSource {
    root = nvimRoot;
    fileset = pkgs.lib.fileset.unions [
      (nvimRoot + "/lua")
      (nvimRoot + "/queries")
    ];
  };
  mkPlugin =
    name: src:
    pkgs.vimUtils.buildVimPlugin {
      pname = name;
      version = src.shortRev or src.rev or "unstable";
      inherit src;
      doCheck = false;
    };
  pluginSpec = name: src: {
    inherit name;
    dir = toString (mkPlugin name src);
  };
  bamlPlugin = (mkPlugin "nvim-baml-syntax" nvim-baml-syntax).overrideAttrs (previousAttrs: {
    # The repository embeds grammar sources under parser/, but Neovim treats
    # every parser/* file as a compiled parser during :checkhealth.
    postInstall = (previousAttrs.postInstall or "") + ''
      rm -rf "$out/parser"
    '';
  });
in
lazyNvim.LazyVim.override {
  lazy-nvim-nix = leanLazyNvim;

  customLuaRC = ''
    vim.g.dotfiles_theme_path = ${builtins.toJSON (toString themeJson)}
    vim.g.loaded_node_provider = 0
    vim.g.loaded_perl_provider = 0
    vim.g.loaded_python3_provider = 0
    vim.g.loaded_ruby_provider = 0
    vim.opt.rtp:prepend(${builtins.toJSON (toString nvimConfig)})
  '';

  extras = [
    "lazyvim.plugins.extras.lang.go"
    "lazyvim.plugins.extras.lang.python"
    "lazyvim.plugins.extras.lang.json"
    "lazyvim.plugins.extras.lang.yaml"
    "lazyvim.plugins.extras.lang.toml"
    "lazyvim.plugins.extras.lang.markdown"
    "lazyvim.plugins.extras.lang.terraform"
    "lazyvim.plugins.extras.lang.git"
    "lazyvim.plugins.extras.lang.typescript"
    "lazyvim.plugins.extras.lang.rust"
    "lazyvim.plugins.extras.ui.edgy"
    "lazyvim.plugins.extras.lang.sql"
    "lazyvim.plugins.extras.coding.mini-surround"
    "lazyvim.plugins.extras.lang.typescript.biome"
    "lazyvim.plugins.extras.lang.nix"
  ];

  extraSpec = [
    (pluginSpec "auto-save.nvim" nvim-auto-save)
    {
      name = "nvim-baml-syntax";
      dir = toString bamlPlugin;
    }
    (pluginSpec "codediff.nvim" nvim-codediff)
    (pluginSpec "git-conflict.nvim" nvim-git-conflict)
    (pluginSpec "monokai-pro.nvim" nvim-monokai-pro)
    (pluginSpec "vim-tmux-navigator" nvim-tmux-navigator)
    { import = "plugins"; }
    (pkgs.lib.generators.mkLuaInline ''require("config.local_spec").find()'')
  ];

  opts = {
    local_spec = false;
    performance.rtp.reset = false;
  };
}
