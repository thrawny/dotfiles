// Pure Git workflow. The QML service executes each argv array without a shell.
function command(state, stage, args) {
    return Object.assign({}, state, { stage: stage, command: ["git", "-C", state.cwd].concat(args) });
}

function failure(state, message) {
    return Object.assign({}, state, { stage: "error", error: message, command: [] });
}

function begin(cwd, input) {
    const branch = input.trim().replace(/^origin\//, "");
    const state = { cwd: cwd, branch: branch };
    if (!branch || branch.startsWith("-"))
        return failure(state, "Enter a valid branch name.");
    return command(state, "validate", ["check-ref-format", "refs/heads/" + branch]);
}

function rows(output) {
    const result = [];
    let row = {};
    for (const field of output.split("\0")) {
        if (!field) {
            if (row.path) result.push(row);
            row = {};
        } else if (field.startsWith("worktree ")) row.path = field.slice(9);
        else if (field.startsWith("branch refs/heads/")) row.branch = field.slice(18);
        else if (field === "bare") row.bare = true;
    }
    if (row.path) result.push(row);
    return result;
}

function add(state, base, tracking) {
    const args = ["worktree", "add"];
    if (base) args.push(tracking ? "--track" : "--no-track", "-b", state.branch);
    args.push("--", state.path, base || state.branch);
    return command(state, "add", args);
}

function advance(state, code, output, error) {
    // Expected absence is handled explicitly; all other failures stop the workflow.
    if (state.stage === "local" && code === 1)
        return command(state, "remote", ["remote", "get-url", "origin"]);
    if (state.stage === "remote" && code === 2)
        return add(state, "HEAD", false);
    if (code !== 0)
        return failure(state, error.trim() || "Git could not complete the worktree operation.");

    switch (state.stage) {
    case "validate":
        return command(state, "list", ["worktree", "list", "--porcelain", "-z"]);
    case "list": {
        const trees = rows(output);
        if (!trees.length || trees[0].bare)
            return failure(state, "Select a project with a main checkout.");
        const repo = trees[0].path;
        const name = repo.slice(repo.lastIndexOf("/") + 1);
        const existing = trees.find(tree => tree.branch === state.branch);
        state = Object.assign({}, state, {
            cwd: repo,
            path: existing ? existing.path : repo + "-worktrees/" + state.branch,
            workspace: name + "/" + state.branch
        });
        if (existing)
            return Object.assign({}, state, { stage: "done", command: [] });
        return command(state, "local", ["show-ref", "--verify", "--quiet", "refs/heads/" + state.branch]);
    }
    case "local":
        return add(state, "", false);
    case "remote":
        return command(state, "inspect", ["ls-remote", "--symref", "origin", "HEAD", "refs/heads/" + state.branch]);
    case "inspect": {
        const lines = output.trim().split("\n");
        const remoteBranch = lines.some(line => line.split("\t")[1] === "refs/heads/" + state.branch);
        const head = lines.find(line => /^ref: refs\/heads\/.+\tHEAD$/.test(line));
        const base = remoteBranch ? state.branch : head ? head.slice(16, head.indexOf("\t")) : "";
        if (!base)
            return failure(state, "Origin has no default branch. Choose an existing branch instead.");
        state = Object.assign({}, state, { base: base, tracking: remoteBranch });
        return command(state, "fetch", ["fetch", "--no-tags", "origin", "+refs/heads/" + base + ":refs/remotes/origin/" + base]);
    }
    case "fetch":
        return add(state, "refs/remotes/origin/" + state.base, state.tracking);
    case "add":
        return Object.assign({}, state, { stage: "done", command: [] });
    default:
        return failure(state, "Unknown worktree operation.");
    }
}
