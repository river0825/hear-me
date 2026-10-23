import Foundation

/// Canonical spellings of words a Taiwanese developer mixes into Chinese speech ("晶晶體").
/// The zh recognizer tends to misspell them (realeasenotes, icone); these are the targets for fuzzy repair.
enum DevVocabulary {
    static let terms: [String] = [
        "release notes", "release", "repo", "repository", "commit", "push", "pull", "pull request", "merge", "rebase",
        "branch", "main", "master", "tag", "deploy", "deployment", "build", "debug", "bug", "test", "testing", "unit test",
        "GitHub", "GitLab", "Gitea", "Xcode", "Swift", "SwiftUI", "Python", "JavaScript", "TypeScript", "React", "Node",
        "npm", "Docker", "Kubernetes", "server", "client", "API", "token", "database", "schema", "migration",
        "frontend", "backend", "backlog", "sprint", "review", "reviewer", "refactor", "config", "feature", "hotfix", "rollback",
        "staging", "production", "icon", "logo", "layout", "prototype", "demo", "email", "Slack", "Notion", "Figma",
        "Chrome", "Safari", "iOS", "macOS", "Android", "iPhone", "iPad", "Mac", "Apple Intelligence", "LINE", "Telegram",
        "Claude", "ChatGPT", "agent", "prompt", "model", "workflow", "pipeline", "CI", "CD", "PR", "issue", "ticket",
        "login", "logout", "signup", "onboarding", "dashboard", "setting", "settings", "update", "upgrade", "install",
        "download", "upload", "sync", "cache", "crash", "log", "console", "terminal", "script", "function", "class",
        "variable", "type", "string", "array", "JSON", "YAML", "Markdown", "HTML", "CSS", "URL", "HTTP", "SSH",
        "Wi-Fi", "Bluetooth", "USB", "CPU", "GPU", "RAM", "SSD", "croc", "zip", "PNG", "PDF", "SVG",
    ]
}
