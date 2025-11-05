{ pkgs, ... }:
{
  services.walker = {
    enable = true;
    package = pkgs.walker;

    settings = {
      search = {
        placeholder = " Type to search...";
      };

      list = {
        max_entries = 200;
        cycle = true;
      };

      builtins = {
        applications = {
          placeholder = " Type to search...";
          prioritize_new = false;
          context_aware = false;
        };

        calc = {
          name = "Calculator";
          prefix = "=";
        };

        emojis = {
          name = "Emojis";
          prefix = ":";
        };

        finder = {
          use_fd = true;
          prefix = ".";
        };
      };
    };

    theme = {
      name = "molokai";
      style = ''
        /* Walker Molokai Theme - Full palette */

        /* Core Molokai colors - true vim colors */
        @define-color molokai-bg #1b1d1e;      /* True Molokai background */
        @define-color molokai-surface #232526;  /* Slightly lighter */
        @define-color molokai-surface-light #293739;
        @define-color molokai-text #f8f8f2;
        @define-color molokai-comment #75715e;

        /* Molokai signature colors */
        @define-color molokai-pink #f92672;      /* Keywords, active */
        @define-color molokai-green #a6e22e;     /* Strings, success */
        @define-color molokai-yellow #e6db74;    /* Strings, highlights */
        @define-color molokai-orange #fd971f;    /* Numbers, warnings */
        @define-color molokai-purple #ae81ff;    /* Constants */
        @define-color molokai-cyan #66d9ef;      /* Functions, info */

        /* Reset all elements */
        #window,
        #box,
        #search,
        #password,
        #input,
        #prompt,
        #clear,
        #typeahead,
        #list,
        child,
        scrollbar,
        slider,
        #item,
        #text,
        #label,
        #sub,
        #activationlabel {
          all: unset;
        }

        * {
          font-family: "CaskaydiaMono Nerd Font", monospace;
          font-size: 13px;
        }

        /* Window */
        #window {
          background: transparent;
          color: @molokai-text;
        }

        /* Main box container */
        #box {
          background: @molokai-bg;
          padding: 20px;
          border: 2px solid @molokai-pink;
          border-radius: 8px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.5);
        }

        /* Search container */
        #search {
          background: @molokai-surface;
          padding: 12px;
          margin-bottom: 12px;
          border-radius: 6px;
          border: 1px solid @molokai-surface-light;
        }

        /* Prompt (search icon) */
        #prompt {
          color: @molokai-pink;
          margin-right: 10px;
          font-size: 16px;
        }

        /* Clear button */
        #clear {
          color: @molokai-comment;
          padding: 0 10px;
        }

        #clear:hover {
          color: @molokai-orange;
        }

        /* Input field */
        #input {
          background: none;
          color: @molokai-text;
          padding: 0;
          caret-color: @molokai-pink;
        }

        #input placeholder {
          opacity: 0.5;
          color: @molokai-comment;
        }

        /* Typeahead suggestion */
        #typeahead {
          color: @molokai-comment;
          opacity: 0.5;
        }

        /* List */
        #list {
          background: transparent;
        }

        /* List items */
        child {
          padding: 10px 14px;
          background: transparent;
          border-radius: 4px;
          margin: 3px 0;
          transition: all 0.15s ease;
          border-left: 2px solid transparent;
        }

        child:selected {
          background: @molokai-surface-light;
          border-left: 2px solid @molokai-pink;
          box-shadow: 0 2px 4px rgba(249, 38, 114, 0.2);
        }

        child:hover {
          background: @molokai-surface;
          border-left: 2px solid @molokai-cyan;
        }

        /* Item layout */
        #item {
          padding: 0;
        }

        #item.active {
          font-style: italic;
        }

        /* Icon */
        #icon {
          margin-right: 10px;
          -gtk-icon-transform: scale(0.8);
        }

        /* Text */
        #text {
          color: @molokai-text;
        }

        #label {
          font-weight: normal;
        }

        /* Selected state */
        child:selected #text,
        child:selected #label {
          color: @molokai-green;
          font-weight: 600;
        }

        child:hover #text,
        child:hover #label {
          color: @molokai-cyan;
        }

        /* Sub text (description) */
        #sub {
          color: @molokai-comment;
          font-size: 11px;
          margin-top: 3px;
          opacity: 0.8;
        }

        child:selected #sub {
          color: @molokai-yellow;
          opacity: 1;
        }

        /* Activation label */
        #activationlabel {
          color: @molokai-purple;
          font-size: 10px;
          margin-left: auto;
          padding-left: 10px;
          font-weight: 600;
        }

        /* Scrollbar styling */
        scrollbar {
          background: @molokai-bg;
          border-radius: 4px;
          margin-left: 4px;
          opacity: 0.3;
        }

        scrollbar slider {
          background: @molokai-comment;
          border-radius: 4px;
          min-width: 6px;
        }

        scrollbar slider:hover {
          background: @molokai-purple;
        }

        /* Spinner */
        #spinner {
          color: @molokai-cyan;
        }

        /* Module switcher bar */
        #bar {
          background: @molokai-bg;
          padding: 8px;
          margin-bottom: 12px;
          border-radius: 6px;
          border: 1px solid @molokai-surface-light;
        }

        .barentry {
          padding: 4px 10px;
          margin: 0 4px;
          border-radius: 4px;
          color: @molokai-comment;
          transition: all 0.2s ease;
          border-bottom: 2px solid transparent;
        }

        .barentry.active {
          background: @molokai-surface-light;
          color: @molokai-pink;
          border-bottom: 2px solid @molokai-pink;
          font-weight: 600;
        }

        .barentry:hover:not(.active) {
          background: @molokai-surface;
          color: @molokai-cyan;
          border-bottom: 2px solid @molokai-cyan;
        }
      '';
    };
  };
}
