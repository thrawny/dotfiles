# Central theme loading and adapters. The canonical palette lives in
# nix/themes/monokai.json; consumers receive it via the `theme` module arg
# and must not carry their own color literals (enforced by bin/check-theme).
{ lib }:
let
  hexRegex = "#[0-9a-fA-F]{6}";
  isHex = v: builtins.isString v && builtins.match hexRegex v != null;

  # Every leaf in these sections must be a #RRGGBB color.
  assertHexLeaves =
    section: value:
    if builtins.isAttrs value then
      lib.all (name: assertHexLeaves "${section}.${name}" value.${name}) (builtins.attrNames value)
    else if builtins.isList value then
      lib.all (v: assertHexLeaves section v) value
    else
      lib.assertMsg (isHex value) "theme: ${section} must be a #RRGGBB color, got ${toString value}";

  hexDigit =
    c:
    let
      idx = lib.strings.stringToCharacters "0123456789abcdef";
      pos = lib.lists.findFirstIndex (d: d == lib.strings.toLower c) null idx;
    in
    assert lib.assertMsg (pos != null) "theme: invalid hex digit ${c}";
    pos;

  hexPair = s: 16 * hexDigit (builtins.substring 0 1 s) + hexDigit (builtins.substring 1 1 s);
in
rec {
  loadTheme =
    path:
    let
      theme = builtins.fromJSON (builtins.readFile path);
      requiredSections = [
        "semantic"
        "syntax"
        "terminal"
        "diff"
        "applications"
      ];
    in
    assert lib.assertMsg (theme.schemaVersion or null == 1) "theme: schemaVersion must be 1";
    assert lib.assertMsg (lib.all (
      s: theme ? ${s}
    ) requiredSections) "theme: missing one of ${toString requiredSections}";
    assert assertHexLeaves "semantic" theme.semantic;
    assert assertHexLeaves "syntax" theme.syntax;
    assert assertHexLeaves "terminal" theme.terminal;
    assert assertHexLeaves "diff" theme.diff;
    theme;

  # "#f92672" -> "249, 38, 114" for CSS rgba() constructions.
  rgb =
    hex:
    lib.concatMapStringsSep ", " (i: toString (hexPair (builtins.substring i 2 hex))) [
      1
      3
      5
    ];

  # One diff contract for Delta wherever it runs (git pager and LazyGit).
  deltaOptions = theme: {
    dark = true;
    syntax-theme = theme.applications.delta.syntaxTheme;
    line-numbers = true;
    plus-style = "syntax \"${theme.diff.added.lineBackground}\"";
    plus-emph-style = "syntax \"${theme.diff.added.emphasisBackground}\"";
    plus-non-emph-style = "syntax \"${theme.diff.added.dimBackground}\"";
    minus-style = "syntax \"${theme.diff.removed.lineBackground}\"";
    minus-emph-style = "syntax \"${theme.diff.removed.emphasisBackground}\"";
    minus-non-emph-style = "syntax \"${theme.diff.removed.dimBackground}\"";
    line-numbers-plus-style = theme.diff.added.foreground;
    line-numbers-minus-style = theme.diff.removed.foreground;
    line-numbers-zero-style = theme.semantic.muted;
  };

  # Render deltaOptions as CLI flags (for LazyGit's diff renderer command).
  deltaArgs =
    theme:
    lib.concatStringsSep " " (
      lib.mapAttrsToList (
        name: value: if value == true then "--${name}" else "--${name}='${toString value}'"
      ) (deltaOptions theme)
    );

  # Pi has no theme inheritance, so its complete theme document is generated.
  piTheme =
    theme:
    let
      pi = theme.applications.pi;
    in
    {
      "$schema" =
        "https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json";
      name = "monokai-pi";
      vars = {
        bg = pi.background;
        bgAlt = pi.backgroundAlt;
        bgPanel = pi.panel;
        inherit (pi) selection green red;
        white = theme.semantic.foreground;
        muted = theme.semantic.muted;
        dim = theme.semantic.dim;
        pink = theme.semantic.accent;
        pinkBright = builtins.elemAt theme.terminal.bright 1;
        purple = theme.semantic.accentAlt;
        cyan = theme.syntax.type;
        yellow = theme.syntax.function;
        orange = theme.semantic.warning;
      };
      colors = {
        accent = "pink";
        border = "pink";
        borderAccent = "pinkBright";
        borderMuted = "dim";
        success = "green";
        error = "red";
        warning = "orange";
        muted = "muted";
        dim = "dim";
        text = "white";
        thinkingText = "muted";

        selectedBg = "selection";
        userMessageBg = "bgPanel";
        userMessageText = "white";
        customMessageBg = "bgAlt";
        customMessageText = "white";
        customMessageLabel = "purple";
        inherit (pi) toolPendingBg toolSuccessBg toolErrorBg;
        toolTitle = "white";
        toolOutput = "muted";

        mdHeading = "yellow";
        mdLink = "cyan";
        mdLinkUrl = "muted";
        mdCode = "green";
        mdCodeBlock = "green";
        mdCodeBlockBorder = "dim";
        mdQuote = "muted";
        mdQuoteBorder = "dim";
        mdHr = "dim";
        mdListBullet = "pink";

        toolDiffAdded = "cyan";
        toolDiffRemoved = "pink";
        toolDiffContext = "muted";

        syntaxComment = pi.comment;
        syntaxKeyword = theme.syntax.keyword;
        syntaxFunction = theme.syntax.function;
        syntaxVariable = theme.syntax.variable;
        syntaxString = theme.syntax.string;
        syntaxNumber = theme.syntax.number;
        syntaxType = theme.syntax.type;
        syntaxOperator = theme.syntax.operator;
        syntaxPunctuation = theme.syntax.punctuation;

        thinkingOff = "dim";
        thinkingMinimal = "muted";
        thinkingLow = "purple";
        thinkingMedium = "pink";
        thinkingHigh = "pinkBright";
        inherit (pi) thinkingXhigh;

        bashMode = "orange";
      };
      export = {
        inherit (pi) pageBg infoBg;
        cardBg = pi.background;
      };
    };

  # Inline diffColors for Pi settings (pi-diff has no external color file
  # support yet); bin/check-theme keeps settings.example.json aligned.
  piDiffColors =
    theme:
    let
      pd = theme.applications.piDiff;
    in
    {
      bgAdd = theme.diff.added.lineBackground;
      bgDel = theme.diff.removed.lineBackground;
      bgAddHighlight = theme.diff.added.emphasisBackground;
      bgDelHighlight = theme.diff.removed.emphasisBackground;
      bgGutterAdd = theme.diff.added.dimBackground;
      bgGutterDel = theme.diff.removed.dimBackground;
      bgEmpty = theme.semantic.background;
      fgAdd = theme.diff.added.foreground;
      fgDel = theme.diff.removed.foreground;
      inherit (pd)
        fgDim
        fgLnum
        fgStripe
        fgSafeMuted
        shikiTheme
        ;
      fgRule = theme.semantic.border;
    };
}
