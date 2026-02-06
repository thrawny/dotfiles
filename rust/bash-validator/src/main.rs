use regex::Regex;
use serde::Deserialize;
use std::io::{self, Read};
use std::process::ExitCode;

#[derive(Deserialize)]
struct HookInput {
    tool_name: Option<String>,
    tool_input: Option<ToolInput>,
}

#[derive(Deserialize)]
struct ToolInput {
    command: Option<String>,
}

fn validate_command(command: &str) -> Vec<&'static str> {
    let mut issues = Vec::new();

    // Check: goimports -w should use golangci-lint instead
    if let Ok(re) = Regex::new(r"^goimports\s+-w\b")
        && re.is_match(command)
    {
        issues.push("Use 'golangci-lint run --fix' instead of goimports -w for comprehensive Go formatting and linting");
    }

    // Check: go build without -o flag
    if let Ok(re) = Regex::new(r"^go\s+build\b")
        && re.is_match(command)
        && !command.contains(" -o ")
    {
        issues.push("Use 'go build -o build/binary_name' to specify output location, or use 'go run' instead to avoid creating untracked binaries");
    }

    // Check: go build -o without proper output directory
    if let Ok(re) = Regex::new(r"^go\s+build\b.*\s-o\s+(\S+)")
        && let Some(caps) = re.captures(command)
        && let Some(output_path) = caps.get(1)
    {
        let path = output_path.as_str();
        let valid_prefixes = [
            "build/", "bin/", "dist/", "out/", "target/", ".build/", "tmp/", "/",
        ];
        if !valid_prefixes.iter().any(|p| path.starts_with(p)) {
            issues.push("Use 'go build -o build/binary_name' with a proper path (e.g., build/, bin/, dist/) to avoid cluttering the project root with binaries");
        }
    }

    // Check: go vet should use golangci-lint run
    if let Ok(re) = Regex::new(r"(?:^|;\s*|&&\s*|\|\|\s*)go\s+vet\b")
        && re.is_match(command)
    {
        issues.push("Use 'golangci-lint run' instead of go vet for comprehensive linting");
    }

    // Check: pip install should use uv add
    if let Ok(re) = Regex::new(r"(?:^|;\s*|&&\s*|\|\|\s*)pip\s+install\b")
        && re.is_match(command)
    {
        issues.push("Use 'uv add <package>' instead of pip install for better dependency management and faster installation");
    }

    // Check: rm handoff.md should use remove-handoff
    if let Ok(re) = Regex::new(r"(?:^|;\s*|&&\s*|\|\|\s*)rm\s+(?:-[rf]+\s+)?(?:\S*/)?handoff\.md\b")
        && re.is_match(command)
    {
        issues.push("Use 'remove-handoff' (preapproved) instead of rm handoff.md");
    }

    issues
}

fn main() -> ExitCode {
    let mut input = String::new();
    if io::stdin().read_to_string(&mut input).is_err() {
        return ExitCode::from(1);
    }

    let hook_input: HookInput = match serde_json::from_str(&input) {
        Ok(h) => h,
        Err(_) => return ExitCode::from(1),
    };

    if hook_input.tool_name.as_deref() != Some("Bash") {
        return ExitCode::SUCCESS;
    }

    let command = match hook_input.tool_input.and_then(|t| t.command) {
        Some(c) => c,
        None => return ExitCode::SUCCESS,
    };

    let issues = validate_command(&command);

    if !issues.is_empty() {
        for message in &issues {
            eprintln!("• {message}");
        }
        return ExitCode::from(2);
    }

    ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rm_handoff_detected() {
        assert!(!validate_command("rm handoff.md").is_empty());
        assert!(!validate_command("rm -f handoff.md").is_empty());
        assert!(!validate_command("rm -rf handoff.md").is_empty());
        assert!(!validate_command("git status && rm handoff.md").is_empty());
        assert!(!validate_command("rm -f /Users/jonas/code/kf1-go/handoff.md").is_empty());
        assert!(!validate_command("rm ./handoff.md").is_empty());
        assert!(!validate_command(
            "remove-handoff 2>/dev/null; rm -f /Users/jonas/code/kf1-go/handoff.md 2>/dev/null; echo \"done\""
        ).is_empty());
        assert!(!validate_command("echo hi; rm handoff.md").is_empty());
        assert!(!validate_command("false || rm -f handoff.md").is_empty());
    }

    #[test]
    fn rm_other_files_allowed() {
        assert!(validate_command("rm other.md").is_empty());
        assert!(validate_command("rm -f something.txt").is_empty());
    }
}
