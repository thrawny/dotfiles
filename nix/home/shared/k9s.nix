_: {
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

    # Skins use YAML anchors, so reference files directly (must be Nix paths, not strings)
    skins = {
      monokai = ./k9s-skins/monokai.yaml;
      dracula = ./k9s-skins/dracula.yaml;
    };
  };
}
