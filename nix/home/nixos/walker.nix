{ walker, ... }:
{
  imports = [ walker.homeManagerModules.default ];

  programs.walker = {
    enable = true;
    runAsService = true;
    config = {
      theme = "molokai";
      keybinds.quick_activate = [ ];
    };
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
