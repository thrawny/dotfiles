{
  pkgs,
  lib,
  walker,
  ...
}:
{
  imports = [ walker.homeManagerModules.default ];

  home.packages = [ pkgs.gh ];

  programs.walker = {
    enable = true;
    runAsService = true;
    config = {
      theme = "molokai";
      keybinds.quick_activate = [ ];
      placeholders."menus:gh" = {
        input = "Search GitHub repositories";
        list = "No matching repositories";
      };
      providers = {
        default = [
          "desktopapplications"
          "calc"
          "websearch"
        ];
        empty = [ "desktopapplications" ];
        prefixes = [
          {
            provider = "providerlist";
            prefix = "?";
          }
          {
            provider = "menus:gh";
            prefix = ",";
          }
        ];
        actions."menus:gh" = [
          {
            action = "open";
            label = "open";
            default = true;
            bind = "Return";
          }
          {
            action = "copy";
            label = "copy url";
            bind = "ctrl c";
          }
          {
            action = "clone";
            label = "clone";
            bind = "ctrl Return";
          }
        ];
      };
    };

    elephant.providers = lib.mkForce [
      "calc"
      "clipboard"
      "desktopapplications"
      "files"
      "menus"
      "providerlist"
      "runner"
      "symbols"
      "websearch"
      "windows"
      "niriactions"
    ];

    elephant.provider.menus.lua.gh = ''
      Name = "gh"
      NamePretty = "GitHub Repos"
      Icon = "github"
      Cache = false
      FixedOrder = true
      SearchPriority = { "keywords" }
      HideFromProviderlist = false
      Description = "Search GitHub repositories"

      local gh = "${pkgs.gh}/bin/gh"
      local xdg_open = "${pkgs.xdg-utils}/bin/xdg-open"
      local wl_copy = "${pkgs.wl-clipboard}/bin/wl-copy"
      local git = "${pkgs.git}/bin/git"
      local mkdir = "${pkgs.coreutils}/bin/mkdir"

      local function shell_quote(s)
        return string.format("%q", tostring(s))
      end

      -- Elephant's menu provider re-scores non-empty queries and then sorts ties
      -- alphabetically by Text. Score against identical per-entry keywords, then
      -- use an invisible zero-width rank prefix to preserve gh's star ordering.
      local function invisible_rank_prefix(rank)
        local zero = "\226\128\139" -- U+200B zero-width space
        local one = "\226\128\140" -- U+200C zero-width non-joiner
        local bits = {}

        for bit = 5, 0, -1 do
          if math.floor(rank / (2 ^ bit)) % 2 == 0 then
            table.insert(bits, zero)
          else
            table.insert(bits, one)
          end
        end

        return table.concat(bits)
      end

      local function matches_query(full_name, query)
        local haystack = full_name:lower()
        local needle = query:lower()

        -- Plain searches should match the repo name, not just the owner/org.
        -- "elephant" should not match "running-elephant/datart".
        if not needle:find("/", 1, true) then
          haystack = haystack:match("[^/]+$") or haystack
        end

        for term in needle:gmatch("%S+") do
          if not haystack:find(term, 1, true) then
            return false
          end
        end

        return true
      end

      local cache = {}
      local cache_ttl_seconds = 300

      function GetEntries(query)
        local entries = {}

        if query == nil or query == "" or #query < 3 then
          return entries
        end

        local now = os.time()
        local cached = cache[query]
        if cached ~= nil and now - cached.time < cache_ttl_seconds then
          return cached.entries
        end

        local cmd = gh .. " search repos " .. shell_quote(query) ..
          " --match name --sort stars --order desc " ..
          " --limit 20 --json fullName,description,url,stargazersCount " ..
          " --jq '.[] | [.fullName, (.description // \"\"), .url, (.stargazersCount|tostring)] | @tsv' 2>&1"

        local handle = io.popen(cmd)
        if not handle then
          return entries
        end

        local output = {}
        local rank = 0
        for line in handle:lines() do
          table.insert(output, line)
          local full_name, description, url, stars = line:match("([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)")

          if full_name ~= nil and url ~= nil and matches_query(full_name, query) then
            rank = rank + 1
            table.insert(entries, {
              Text = invisible_rank_prefix(rank) .. full_name,
              Subtext = "★ " .. (stars or "0") .. "  " .. (description or ""),
              Value = url,
              Icon = "github",
              Keywords = { query },
              Actions = {
                open = xdg_open .. " %VALUE%",
                copy = wl_copy .. " %VALUE%",
                clone = mkdir .. " -p ~/code && " .. git .. " -C ~/code clone %VALUE%",
              },
            })
          end
        end

        handle:close()

        if #entries == 0 and #output > 0 then
          table.insert(entries, {
            Text = "GitHub search returned no matching repos",
            Subtext = table.concat(output, "  "):sub(1, 240),
            Icon = "dialog-warning",
            Keywords = { query },
          })
        end

        cache[query] = { time = now, entries = entries }
        return entries
      end
    '';

    themes.molokai.style = ''
      @define-color window_bg_color #1c1c1c;
      @define-color accent_bg_color #f92672;
      @define-color theme_fg_color #f8f8f2;
      @define-color error_bg_color #f92672;
      @define-color error_fg_color #f8f8f2;

      * {
        all: unset;
      }

      popover {
        background: lighter(@window_bg_color);
        border: 1px solid @accent_bg_color;
        border-radius: 18px;
        padding: 10px;
      }

      .normal-icons {
        -gtk-icon-size: 16px;
      }

      .large-icons {
        -gtk-icon-size: 32px;
      }

      scrollbar {
        opacity: 0;
      }

      .box-wrapper {
        box-shadow: 0 19px 38px rgba(0, 0, 0, 0.3), 0 15px 12px rgba(0, 0, 0, 0.22);
        background: @window_bg_color;
        padding: 20px;
        border-radius: 20px;
        border: 1px solid darker(@accent_bg_color);
      }

      .preview-box,
      .elephant-hint,
      .placeholder {
        color: @theme_fg_color;
      }

      .search-container {
        border-radius: 10px;
      }

      .input placeholder {
        opacity: 0.5;
      }

      .input selection {
        background: #49483e;
      }

      .input {
        caret-color: @accent_bg_color;
        background: lighter(@window_bg_color);
        padding: 10px;
        color: @theme_fg_color;
      }

      .list {
        color: @theme_fg_color;
      }

      .item-box {
        border-radius: 10px;
        padding: 10px;
      }

      .item-quick-activation {
        background: alpha(@accent_bg_color, 0.25);
        border-radius: 5px;
        padding: 10px;
      }

      child:selected .item-box {
        background: alpha(@accent_bg_color, 0.25);
      }

      child:selected .item-text {
        color: #a6e22e;
      }

      .item-subtext {
        font-size: 12px;
        color: #75715e;
      }

      .providerlist .item-subtext {
        font-size: unset;
        opacity: 0.75;
      }

      .item-image-text {
        font-size: 28px;
      }

      .preview {
        border: 1px solid alpha(@accent_bg_color, 0.25);
        border-radius: 10px;
        color: @theme_fg_color;
      }

      .calc .item-text {
        font-size: 24px;
      }

      .symbols .item-image {
        font-size: 24px;
      }

      .todo.done .item-text-box {
        opacity: 0.25;
      }

      .todo.urgent {
        font-size: 24px;
      }

      .todo.active {
        font-weight: bold;
      }

      .bluetooth.disconnected {
        opacity: 0.5;
      }

      .preview .large-icons {
        -gtk-icon-size: 64px;
      }

      .keybinds {
        padding-top: 10px;
        border-top: 1px solid lighter(@window_bg_color);
        font-size: 12px;
        color: @theme_fg_color;
      }

      .keybind-button {
        opacity: 0.5;
      }

      .keybind-button:hover {
        opacity: 0.75;
        cursor: pointer;
      }

      .keybind-bind {
        text-transform: lowercase;
        opacity: 0.35;
      }

      .keybind-label {
        padding: 2px 4px;
        border-radius: 4px;
        border: 1px solid @theme_fg_color;
      }

      .error {
        padding: 10px;
        background: @error_bg_color;
        color: @error_fg_color;
      }

      :not(.calc).current {
        font-style: italic;
      }

      .preview-content.archlinuxpkgs {
        font-family: monospace;
      }
    '';
  };
}
