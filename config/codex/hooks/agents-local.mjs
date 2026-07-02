#!/usr/bin/env node
import { existsSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

const PRIMARY_LOCAL_INSTRUCTIONS_FILE = "AGENTS.local.md";
const FALLBACK_LOCAL_INSTRUCTIONS_FILE = "CLAUDE.local.md";
const LOCAL_INSTRUCTIONS_FILES = [
  PRIMARY_LOCAL_INSTRUCTIONS_FILE,
  FALLBACK_LOCAL_INSTRUCTIONS_FILE,
];

function readStdinJson() {
  try {
    const input = readFileSync(0, "utf8").trim();
    return input ? JSON.parse(input) : {};
  } catch {
    return {};
  }
}

function isFile(filePath) {
  try {
    return statSync(filePath).isFile();
  } catch {
    return false;
  }
}

function findGitRoot(cwd) {
  let dir = path.resolve(cwd);
  while (true) {
    if (existsSync(path.join(dir, ".git"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return undefined;
    dir = parent;
  }
}

function directoriesFromRootToCwd(root, cwd) {
  const absoluteRoot = path.resolve(root);
  const absoluteCwd = path.resolve(cwd);
  const relative = path.relative(absoluteRoot, absoluteCwd);
  if (!relative) return [absoluteRoot];

  const dirs = [absoluteRoot];
  let current = absoluteRoot;
  for (const part of relative.split(path.sep)) {
    if (!part || part === "..") continue;
    current = path.join(current, part);
    dirs.push(current);
  }
  return dirs;
}

function localInstructionPathForDir(dir) {
  for (const fileName of LOCAL_INSTRUCTIONS_FILES) {
    const filePath = path.join(dir, fileName);
    if (isFile(filePath)) return filePath;
  }
  return undefined;
}

function findLocalInstructionPaths(cwd) {
  const absoluteCwd = path.resolve(cwd);
  const root = findGitRoot(absoluteCwd) ?? absoluteCwd;
  return directoriesFromRootToCwd(root, absoluteCwd).flatMap((dir) => {
    const filePath = localInstructionPathForDir(dir);
    return filePath ? [filePath] : [];
  });
}

function loadLocalInstructions(cwd) {
  return findLocalInstructionPaths(cwd).flatMap((filePath) => {
    try {
      const content = readFileSync(filePath, "utf8").trim();
      return content ? [{ path: filePath, content }] : [];
    } catch {
      return [];
    }
  });
}

function renderLocalInstructions(files, _cwd) {
  return files.map((file) => file.content).join("\n\n");
}

const hookInput = readStdinJson();
const cwd = typeof hookInput.cwd === "string" && hookInput.cwd ? hookInput.cwd : process.cwd();
const localInstructions = loadLocalInstructions(cwd);
const hookEventName =
  typeof hookInput.hook_event_name === "string" && hookInput.hook_event_name
    ? hookInput.hook_event_name
    : "SessionStart";

if (localInstructions.length > 0) {
  process.stdout.write(
    `${JSON.stringify({
      hookSpecificOutput: {
        hookEventName,
        additionalContext: renderLocalInstructions(localInstructions, cwd),
      },
    })}\n`,
  );
}
