{
  agentAssets,
  pkgs,
  ...
}:
{
  home.file =
    agentAssets.skillFiles "claude" (agentAssets.skillEntriesFor pkgs "claude")
    // agentAssets.skillFiles "codex" (agentAssets.skillEntriesFor pkgs "codex")
    // agentAssets.skillFiles "pi" (agentAssets.skillEntriesFor pkgs "pi");
}
