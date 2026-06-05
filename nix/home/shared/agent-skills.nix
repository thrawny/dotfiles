{
  agentAssets,
  ...
}:
{
  home.file =
    agentAssets.skillFiles "claude" (agentAssets.skillEntriesFor "claude")
    // agentAssets.skillFiles "codex" (agentAssets.skillEntriesFor "codex")
    // agentAssets.skillFiles "pi" (agentAssets.skillEntriesFor "pi");
}
