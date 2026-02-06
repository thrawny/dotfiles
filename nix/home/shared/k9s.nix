_:
let
  # Monokai palette (matches Ghostty Molokai theme and tmux status bar)
  fg = "#f0f0f0";
  bg = "#1c1c1c";
  currentLine = "#2d2a2e";
  selection = "#49483e";
  comment = "#808080";
  cyan = "#78dce8";
  green = "#a9dc76";
  pink = "#ff6188";
  purple = "#ab9df2";
  yellow = "#ffd866";
in
{
  programs.k9s = {
    enable = true;
    # k9s is installed via packages.nix
    package = null;

    settings = {
      k9s = {
        liveViewAutoRefresh = false;
        refreshRate = 2;
        maxConnRetry = 5;
        readOnly = false;
        noExitOnCtrlC = false;
        ui = {
          enableMouse = false;
          headless = false;
          logoless = false;
          crumbsless = false;
          reactive = false;
          noIcons = false;
          defaultsToFullScreen = false;
          skin = "monokai";
        };
        skipLatestRevCheck = false;
        disablePodCounting = false;
        shellPod = {
          image = "busybox:1.35.0";
          namespace = "default";
          limits = {
            cpu = "100m";
            memory = "100Mi";
          };
        };
        imageScans = {
          enable = false;
          exclusions = {
            namespaces = [ ];
            labels = { };
          };
        };
        logger = {
          tail = 100;
          buffer = 5000;
          sinceSeconds = -1;
          textWrap = false;
          showTime = false;
        };
        thresholds = {
          cpu = {
            critical = 90;
            warn = 70;
          };
          memory = {
            critical = 90;
            warn = 70;
          };
        };
      };
    };

    aliases = {
      dp = "deployments";
      sec = "v1/secrets";
      jo = "jobs";
      cr = "clusterroles";
      crb = "clusterrolebindings";
      ro = "roles";
      rb = "rolebindings";
      np = "networkpolicies";
    };

    views = {
      "v1/pods" = {
        sortColumn = "NAMESPACE:asc";
        columns = [
          "NAMESPACE"
          "NAME"
          "PF"
          "READY"
          "STATUS"
          "RESTARTS"
          "AGE"
          "CPU"
          "MEM"
          "%CPU/R"
          "%CPU/L"
          "%MEM/R"
          "%MEM/L"
          "IP"
          "NODE"
        ];
      };
      "v1/nodes" = {
        sortColumn = "NAME:asc";
        columns = [
          "NAME"
          "STATUS"
          "AGE"
          "VERSION"
          "CAPACITY_TYPE:.metadata.labels.karpenter\\.sh/capacity-type"
          "INSTANCE_TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type"
          "TAINTS"
          "PODS"
          "CPU"
          "CPU/A"
          "%CPU"
          "MEM"
          "MEM/A"
          "%MEM"
          "ROLE|H"
          "ARCH|H"
          "OS-IMAGE|H"
          "KERNEL|H"
          "INTERNAL-IP|H"
          "EXTERNAL-IP|H"
          "GPU/A|H"
          "GPU/C|H"
          "SH-GPU/A|H"
          "SH-GPU/C|H"
          "LABELS|H"
          "VALID|H"
        ];
      };
    };

    skins.monokai = {
      k9s = {
        body = {
          fgColor = fg;
          bgColor = bg;
          logoColor = purple;
        };
        prompt = {
          fgColor = fg;
          bgColor = bg;
          suggestColor = purple;
        };
        info = {
          fgColor = pink;
          sectionColor = fg;
        };
        dialog = {
          fgColor = fg;
          bgColor = currentLine;
          buttonFgColor = fg;
          buttonBgColor = purple;
          buttonFocusFgColor = bg;
          buttonFocusBgColor = yellow;
          labelFgColor = yellow;
          fieldFgColor = fg;
        };
        frame = {
          border = {
            fgColor = selection;
            focusColor = purple;
          };
          menu = {
            fgColor = fg;
            keyColor = pink;
            numKeyColor = pink;
          };
          crumbs = {
            fgColor = fg;
            bgColor = currentLine;
            activeColor = yellow;
          };
          status = {
            newColor = cyan;
            modifyColor = purple;
            addColor = green;
            errorColor = pink;
            highlightColor = yellow;
            killColor = comment;
            completedColor = comment;
          };
          title = {
            fgColor = fg;
            bgColor = currentLine;
            highlightColor = yellow;
            counterColor = purple;
            filterColor = pink;
          };
        };
        views = {
          charts = {
            bgColor = bg;
            defaultDialColors = [
              purple
              pink
            ];
            defaultChartColors = [
              purple
              pink
            ];
          };
          table = {
            fgColor = fg;
            bgColor = bg;
            header = {
              fgColor = fg;
              bgColor = currentLine;
              sorterColor = cyan;
            };
          };
          xray = {
            fgColor = fg;
            bgColor = bg;
            cursorColor = currentLine;
            graphicColor = purple;
            showIcons = false;
          };
          yaml = {
            keyColor = pink;
            colonColor = comment;
            valueColor = fg;
          };
          logs = {
            fgColor = fg;
            bgColor = bg;
            indicator = {
              fgColor = fg;
              bgColor = currentLine;
              toggleOnColor = green;
              toggleOffColor = comment;
            };
          };
        };
      };
    };
  };
}
