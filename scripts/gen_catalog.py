#!/usr/bin/env python3
"""Generate the expanded agent_resource_catalog.json (>=45 skills, >=25 MCP).

Keeps the 6 existing skills (bundlePath) and 2 existing MCP servers, adds the
rest with embeddedMarkdown. Output is written to the catalog file.
"""
import json
from pathlib import Path

CAT = Path(__file__).resolve().parent.parent / "myCoder/Sources/Resources/Catalog/agent_resource_catalog.json"


def skill_md(name, desc, body):
    return (
        "---\n"
        f"name: {name}\n"
        f"description: {desc}\n"
        "---\n"
        f"{body.strip()}\n"
    )


skills = []

# ── Existing 6 (keep bundlePath) ────────────────────────────────────────────
skills += [
    {"id": "lazyweb", "name": "Lazyweb", "description": "Real product screenshots and UI patterns for design research, onboarding, paywalls, and dashboards.", "category": "Design", "bundlePath": "skill-lazyweb.md", "relatedMCPIds": ["lazyweb"], "version": "1.0.0", "sourceRepo": "mimo-macos"},
    {"id": "canvas", "name": "Canvas", "description": "Build interactive React canvases for charts, tables, timelines, and data-heavy deliverables.", "category": "Productivity", "bundlePath": "skill-canvas.md", "version": "1.0.0", "sourceRepo": "mimo-macos"},
    {"id": "create-skill", "name": "Create Skill", "description": "Author new Cursor agent skills with the correct SKILL.md structure and packaging.", "category": "Agent", "bundlePath": "skill-create-skill.md", "version": "1.0.0", "sourceRepo": "mimo-macos"},
    {"id": "create-hook", "name": "Create Hook", "description": "Create Cursor hooks.json scripts to automate behavior around agent events.", "category": "Agent", "bundlePath": "skill-create-hook.md", "version": "1.0.0", "sourceRepo": "mimo-macos"},
    {"id": "review-bugbot", "name": "Review Bugbot", "description": "Launch a Bugbot subagent to review local branch or uncommitted changes.", "category": "Quality", "bundlePath": "skill-review-bugbot.md", "version": "1.0.0", "sourceRepo": "mimo-macos"},
    {"id": "systematic-debugging", "name": "Systematic Debugging", "description": "Structured debugging workflow before proposing fixes for bugs and test failures.", "category": "Quality", "bundlePath": "skill-systematic-debugging.md", "version": "1.0.0", "sourceRepo": "mimo-macos"},
]

# ── Documents (anthropics/skills document-skills) ───────────────────────────
docs_body = (
    "When the user asks to read, extract, or author a {kind} document, use the "
    "appropriate library to parse/produce it. Never paste raw base64 as the "
    "document — write a real file and report its path. Preserve formatting, "
    "styles, and tables. Prefer streaming large documents to disk."
)
for sid, nm, kind in [
    ("pdf", "PDF Documents", "PDF"),
    ("docx", "DOCX Documents", "Word DOCX"),
    ("pptx", "PPTX Documents", "PowerPoint PPTX"),
    ("xlsx", "XLSX Documents", "Excel XLSX"),
]:
    skills.append({
        "id": sid, "name": nm,
        "description": f"Read, extract, and author {kind} documents.",
        "category": "Documents",
        "embeddedMarkdown": skill_md(sid, f"Read, extract, and author {kind} documents.", docs_body.format(kind=kind)),
        "version": "1.0.0", "sourceRepo": "anthropics/skills",
        "dependencies": [],
    })

# ── Development (anthropics/skills example-skills) ───────────────────────────
dev_skills = [
    ("mcp-builder", "MCP Builder", "Generate scaffolded MCP servers (stdio or HTTP) from a tool description, including package manifests and tool handlers.", ["node>=18"]),
    ("web-artifacts-builder", "Web Artifacts Builder", "Produce self-contained interactive HTML/JS artifacts (charts, demos, widgets) from a prompt.", []),
    ("webapp-testing", "Webapp Testing", "Drive end-to-end tests of a local webapp through a browser MCP, report failures with repro steps.", ["playwright-mcp"]),
    ("skill-creator", "Skill Creator", "Meta-skill: author a new SKILL.md with correct frontmatter, trigger description, and instructions.", []),
]
for sid, nm, desc, deps in dev_skills:
    body = f"# {nm}\n\nUse this skill when the user asks to: {desc}\n\nFollow the established SKILL.md structure. Keep instructions concrete and side-effect-aware. Always verify the result before declaring success."
    skills.append({"id": sid, "name": nm, "description": desc, "category": "Development",
                    "embeddedMarkdown": skill_md(sid, desc, body),
                    "version": "1.0.0", "sourceRepo": "anthropics/skills",
                    "dependencies": deps})

# ── Design / Creative ───────────────────────────────────────────────────────
design_skills = [
    ("canvas-design", "Canvas Design", "Design interactive data canvases (charts, tables, timelines) with consistent visual language.", []),
    ("brand-guidelines", "Brand Guidelines", "Apply brand colors, type scale, spacing, and voice consistently across generated UI.", []),
    ("algorithmic-art", "Algorithmic Art", "Generate procedural/generative art (p5.js, SVG, shaders) from a creative prompt.", []),
]
for sid, nm, desc, deps in design_skills:
    body = f"# {nm}\n\n{desc}\n\nAnchor every visual decision to the design system. Prefer composition over duplication. Export assets in the requested format."
    skills.append({"id": sid, "name": nm, "description": desc, "category": "Design",
                    "embeddedMarkdown": skill_md(sid, desc, body),
                    "version": "1.0.0", "sourceRepo": "anthropics/skills",
                    "dependencies": deps})

# ── Workflow (superpowers) ──────────────────────────────────────────────────
wf = [
    ("brainstorming", "Brainstorming", "Run a structured brainstorm: diverge → cluster → converge → pick, recording each step.", []),
    ("dispatching-parallel-agents", "Dispatching Parallel Agents", "Split a task into independent subtasks and fan them out to subagents, then merge results.", []),
    ("executing-plans", "Executing Plans", "Execute a written plan step by step, marking each step done only after verification.", []),
    ("finishing-dev-branch", "Finishing a Development Branch", "Land a branch cleanly: tests green, deslop, review, merge/PR.", []),
]
for sid, nm, desc, deps in wf:
    body = f"# {nm}\n\n{desc}\n\nProceed methodically. Do not skip verification. Record decisions and blockers explicitly."
    skills.append({"id": sid, "name": nm, "description": desc, "category": "Workflow",
                    "embeddedMarkdown": skill_md(sid, desc, body),
                    "version": "1.0.0", "sourceRepo": "obra/superpowers",
                    "dependencies": deps})

# ── Quality (superpowers) ──────────────────────────────────────────────────
q = [
    ("receiving-code-review", "Receiving Code Review", "Triage review comments: address, defer, or push back with rationale; update the PR.", []),
    ("requesting-code-review", "Requesting Code Review", "Prepare a branch for review: summarize intent, call out risks, request focused feedback.", []),
    ("subagent-driven-development", "Subagent-Driven Development", "Drive implementation by delegating well-scoped units of work to subagents.", []),
    ("test-driven-development", "Test-Driven Development", "Red-green-refactor: write a failing test, make it pass, then refactor.", []),
]
for sid, nm, desc, deps in q:
    body = f"# {nm}\n\n{desc}\n\nWrite the test first. Keep changes minimal and behavior-preserving. Never declare done without a green test."
    skills.append({"id": sid, "name": nm, "description": desc, "category": "Quality",
                    "embeddedMarkdown": skill_md(sid, desc, body),
                    "version": "1.0.0", "sourceRepo": "obra/superpowers",
                    "dependencies": deps})

# ── Workflow / Meta (superpowers) ───────────────────────────────────────────
wm = [
    ("using-git-worktrees", "Using Git Worktrees", "Isolate parallel work in git worktrees; never edit in a shared checkout.", []),
    ("verification-before-completion", "Verification Before Completion", "Verify the change by running/building before claiming it is done.", []),
    ("writing-plans", "Writing Plans", "Write a clear, step-by-step plan with acceptance criteria before implementing.", []),
    ("writing-skills", "Writing Skills", "Author reusable SKILL.md files following the standard frontmatter and instruction shape.", []),
]
for sid, nm, desc, deps in wm:
    body = f"# {nm}\n\n{desc}\n\nPlans and skills are reusable artifacts: keep them general, concrete, and side-effect-aware."
    skills.append({"id": sid, "name": nm, "description": desc, "category": "Workflow",
                    "embeddedMarkdown": skill_md(sid, desc, body),
                    "version": "1.0.0", "sourceRepo": "obra/superpowers",
                    "dependencies": deps})

# ── Engineering (cursor-team-kit) ───────────────────────────────────────────
eng = [
    ("check-compiler-errors", "Check Compiler Errors", "Run the project's typecheck/build and fix every reported error before proceeding.", []),
    ("control-cli", "Control CLI", "Drive the project's CLI tooling, parse its output, and act on failures.", []),
    ("control-ui", "Control UI", "Drive the project's UI for verification (via a browser MCP) and report visual regressions.", ["playwright-mcp", "chrome-devtools-mcp"]),
    ("deslop", "Deslop", "Remove dead code, duplicated logic, and cosmetic leftovers; keep behavior identical.", []),
    ("fix-ci", "Fix CI", "Reproduce the failing CI job locally, fix the root cause, and confirm green before pushing.", []),
]
for sid, nm, desc, deps in eng:
    body = f"# {nm}\n\n{desc}\n\nTreat CI/compiler output as ground truth. Fix root causes, not symptoms."
    skills.append({"id": sid, "name": nm, "description": desc, "category": "Engineering",
                    "embeddedMarkdown": skill_md(sid, desc, body),
                    "version": "1.0.0", "sourceRepo": "cursor-team-kit",
                    "dependencies": deps})

# ── Git / CI (cursor-team-kit) ──────────────────────────────────────────────
gitci = [
    ("fix-merge-conflicts", "Fix Merge Conflicts", "Resolve merge conflicts by understanding both sides, keeping intent, and re-testing.", []),
    ("get-pr-comments", "Get PR Comments", "Fetch and summarize PR review comments for action.", []),
    ("loop-on-ci", "Loop on CI", "Iterate pushing fixes until CI is green, each time addressing the real failure.", []),
    ("make-pr-easy-to-review", "Make PR Easy to Review", "Scope PRs small, with a clear description and self-review notes.", []),
    ("new-branch-and-pr", "New Branch and PR", "Create a focused branch, commit, push, and open a PR with a templated description.", []),
]
for sid, nm, desc, deps in gitci:
    body = f"# {nm}\n\n{desc}\n\nSmall, reviewable PRs win. Keep diffs focused and descriptions honest."
    skills.append({"id": sid, "name": nm, "description": desc, "category": "Git/CI",
                    "embeddedMarkdown": skill_md(sid, desc, body),
                    "version": "1.0.0", "sourceRepo": "cursor-team-kit",
                    "dependencies": deps})

# ── Reporting (cursor-team-kit) ─────────────────────────────────────────────
rep = [
    ("review-and-ship", "Review and Ship", "Self-review the diff, confirm tests, and ship.", []),
    ("run-smoke-tests", "Run Smoke Tests", "Run the project's smoke tests and report pass/fail with logs.", []),
    ("verify-this", "Verify This", "Verify a specific change/claim by running it, not by asserting it.", []),
    ("weekly-review", "Weekly Review", "Summarize the week's work: what shipped, what's blocked, what's next.", []),
    ("what-did-i-get-done", "What Did I Get Done", "Produce a changelog of completed work from git history and notes.", []),
    ("workflow-from-chats", "Workflow From Chats", "Turn a chat conversation into a repeatable workflow or plan.", []),
]
for sid, nm, desc, deps in rep:
    body = f"# {nm}\n\n{desc}\n\nReport facts with evidence (logs, diffs, links), not assertions."
    skills.append({"id": sid, "name": nm, "description": desc, "category": "Reporting",
                    "embeddedMarkdown": skill_md(sid, desc, body),
                    "version": "1.0.0", "sourceRepo": "cursor-team-kit",
                    "dependencies": deps})

# ── Design (appdisign) ──────────────────────────────────────────────────────
appdisign = [
    ("design-create", "Design Create", "Create new UI/screens from a brief, following the design system.", ["figma-mcp"]),
    ("design-umbrella", "Design Umbrella", "Umbrella skill routing design requests to the right sub-skill.", ["figma-mcp", "pablooo-mcp"]),
    ("explain-flow", "Explain Flow", "Explain a user/feature flow step by step with diagrams.", []),
    ("propose-ui-changes", "Propose UI Changes", "Propose concrete UI changes with before/after and rationale.", ["pablooo-mcp"]),
    ("quick-search", "Quick Search", "Quickly find a file, symbol, or reference in the project.", []),
    ("design-update", "Design Update", "Update an existing screen while preserving design tokens and layout.", ["figma-mcp"]),
]
for sid, nm, desc, deps in appdisign:
    body = f"# {nm}\n\n{desc}\n\nAnchor to design tokens. Prefer incremental, reviewable changes."
    skills.append({"id": sid, "name": nm, "description": desc, "category": "Design",
                    "embeddedMarkdown": skill_md(sid, desc, body),
                    "version": "1.0.0", "sourceRepo": "appdisign",
                    "dependencies": deps})

# ── Media ───────────────────────────────────────────────────────────────────
skills.append({
    "id": "remotion-video", "name": "Remotion Video", "category": "Media",
    "description": "Generate React-based Remotion videos/compositions from a storyboard.",
    "embeddedMarkdown": skill_md("remotion-video", "Generate React-based Remotion videos/compositions from a storyboard.",
                                 "Render via the Remotion CLI. Keep compositions parameterized. Export to the requested format and report the path."),
    "version": "1.0.0", "sourceRepo": "remotion-dev/remotion", "dependencies": ["node>=18"],
})

# ───────────────────────── MCP servers ──────────────────────────────────────
mcps = []
# Existing 2
mcps += [
    {"id": "lazyweb", "name": "Lazyweb", "description": "Design research MCP with screenshot library, search, and health checks.", "category": "Design", "url": "https://www.lazyweb.com/mcp", "version": "1.0.0", "sourceRepo": "lazyweb",
     "fetchInstallToken": {"url": "https://www.lazyweb.com/api/mcp/install-token", "method": "POST", "body": "{}", "tokenKeys": ["token", "installToken", "access_token"]}},
    {"id": "filesystem", "name": "Filesystem", "description": "Read and write files in your home directory via MCP (requires Node.js 18+).", "category": "Development", "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "{HOME}"], "version": "1.0.0", "sourceRepo": "modelcontextprotocol/servers", "requires": ["node>=18"], "transport": "stdio"},
]
# Core reference servers
core = [
    ("fetch", "Fetch", "Fetch web content and convert to markdown for the model.", "npx", ["-y", "@modelcontextprotocol/server-fetch"], ["node>=18"]),
    ("memory", "Memory", "Persistent knowledge graph memory store across sessions.", "npx", ["-y", "@modelcontextprotocol/server-memory"], ["node>=18"]),
    ("sequential-thinking", "Sequential Thinking", "Structured multi-step reasoning and planning tool.", "npx", ["-y", "@modelcontextprotocol/server-sequential-thinking"], ["node>=18"]),
    ("time", "Time", "Current time, timezone conversion, and clock utilities.", "npx", ["-y", "@modelcontextprotocol/server-time"], ["node>=18"]),
    ("everything", "Everything", "Reference MCP exercising every protocol feature (testing/demo).", "npx", ["-y", "@modelcontextprotocol/server-everything"], ["node>=18"]),
    ("git", "Git", "Git operations: log, diff, status, blame, branch management.", "uvx", ["mcp-server-git"], ["python3"]),
]
for sid, nm, desc, cmd, args, req in core:
    mcps.append({"id": sid, "name": nm, "description": desc, "category": "Core", "command": cmd, "args": args, "version": "1.0.0", "sourceRepo": "modelcontextprotocol/servers", "requires": req, "transport": "stdio"})

# Data / Integrations (archived but widely used)
data = [
    ("postgres", "Postgres", "Query and inspect a PostgreSQL database (read-only by default).", "npx", ["-y", "@modelcontextprotocol/server-postgres", "{DATABASE_URL}"], ["node>=18"], {"DATABASE_URL": ""}),
    ("sqlite", "SQLite", "Query and inspect a SQLite database file.", "uvx", ["mcp-server-sqlite", "--db-path", "{DB_PATH}"], ["python3"], None),
    ("slack", "Slack", "Search and interact with Slack workspaces.", "npx", ["-y", "@modelcontextprotocol/server-slack"], ["node>=18"], None),
    ("google-drive", "Google Drive", "Search and read files from Google Drive.", "npx", ["-y", "@modelcontextprotocol/server-google-drive"], ["node>=18"], None),
    ("brave-search", "Brave Search", "Web and local search via the Brave Search API.", "npx", ["-y", "@modelcontextprotocol/server-brave-search"], ["node>=18"], {"BRAVE_API_KEY": ""}),
    ("redis", "Redis", "Read and inspect a Redis instance.", "npx", ["-y", "@modelcontextprotocol/server-redis"], ["node>=18"], None),
]
for sid, nm, desc, cmd, args, req, env in data:
    item = {"id": sid, "name": nm, "description": desc, "category": "Data/Integrations", "command": cmd, "args": args, "version": "1.0.0", "sourceRepo": "modelcontextprotocol/servers-archived", "requires": req, "transport": "stdio"}
    if env:
        item["env"] = env
    mcps.append(item)

# Development
mcps.append({"id": "github", "name": "GitHub", "description": "GitHub repos, issues, PRs, and actions via the official GitHub MCP server.", "category": "Development", "command": "npx", "args": ["-y", "@github/github-mcp-server"], "version": "1.0.0", "sourceRepo": "github/github-mcp-server", "requires": ["node>=18"], "transport": "stdio", "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": ""}})

# Business
mcps += [
    {"id": "stripe", "name": "Stripe", "description": "Inspect Stripe customers, charges, and events.", "category": "Business", "command": "npx", "args": ["-y", "@stripe/mcp"], "version": "1.0.0", "sourceRepo": "stripe/stripe-mcp", "requires": ["node>=18"], "transport": "stdio", "env": {"STRIPE_SECRET_KEY": ""}},
    {"id": "linear", "name": "Linear", "description": "Read and create Linear issues and projects.", "category": "Business", "url": "https://mcp.linear.app/sse", "version": "1.0.0", "sourceRepo": "linear/linear-mcp", "transport": "http"},
]

# Browser Automation (priority)
browser = [
    ("playwright", "Playwright", "Full browser automation: navigate, click, fill, screenshot, assert via Playwright.", "npx", ["-y", "@playwright/mcp"], ["node>=18"]),
    ("puppeteer", "Puppeteer", "Headless Chrome automation via Puppeteer (archived but popular).", "npx", ["-y", "@modelcontextprotocol/server-puppeteer"], ["node>=18"]),
    ("chrome-devtools", "Chrome DevTools", "CDP-based inspection, profiling, and debugging of a live Chrome instance.", "npx", ["-y", "chrome-devtools-mcp"], ["node>=18"]),
    ("browserbase", "Browserbase", "Managed headless browsers in the cloud for agent workflows.", "npx", ["-y", "@browserbasehq/mcp-server"], ["node>=18"]),
]
for sid, nm, desc, cmd, args, req in browser:
    mcps.append({"id": sid, "name": nm, "description": desc, "category": "Browser Automation", "command": cmd, "args": args, "version": "1.0.0", "sourceRepo": "modelcontextprotocol/servers", "requires": req, "transport": "stdio", "env": ({"BROWSERBASE_API_KEY": ""} if sid == "browserbase" else None)})

# Design (priority)
mcps += [
    {"id": "figma", "name": "Figma", "description": "Figma Dev Mode MCP — pull designs, components, and tokens from Figma files.", "category": "Design", "command": "npx", "args": ["-y", "figma-developer-mcp", "--figma-api-key={FIGMA_API_KEY}"], "version": "1.0.0", "sourceRepo": "GLips/Figma-Context-MCP", "requires": ["node>=18"], "transport": "stdio", "env": {"FIGMA_API_KEY": ""}},
    {"id": "pablooo", "name": "Pablooo", "description": "Premium UI reference screenshots via mcp.pablooo.club for design inspiration.", "category": "Design", "url": "https://mcp.pablooo.club/mcp", "version": "1.0.0", "sourceRepo": "pablooo", "transport": "http"},
]

# Extras to round out >=25
mcps += [
    {"id": "context7", "name": "Context7", "description": "Up-to-date library/framework documentation lookup for accurate code.", "category": "Productivity", "command": "npx", "args": ["-y", "@upstash/context7-mcp"], "version": "1.0.0", "sourceRepo": "upstash/context7", "requires": ["node>=18"], "transport": "stdio"},
    {"id": "shell", "name": "Shell", "description": "Execute sandboxed shell commands and return output (with user approval).", "category": "Development", "command": "npx", "args": ["-y", "@wonderwhy-95/desktop-commander"], "version": "1.0.0", "sourceRepo": "wonderwhy-95/desktop-commander", "requires": ["node>=18"], "transport": "stdio"},
    {"id": "everart", "name": "EverArt", "description": "Generate design images/assets via EverArt for prototyping.", "category": "Design", "url": "https://mcp.everart.ai/mcp", "version": "1.0.0", "sourceRepo": "everart", "transport": "http"},
]

# fix the pablooo/everart/shell Name keys (typo guard) -> normalize to "name"
for m in mcps:
    m.pop("Name", None)

doc = {
    "version": 2,
    "updatedAt": "2026-07-23",
    "skills": skills,
    "mcpServers": mcps,
}

assert len(skills) >= 45, f"skills={len(skills)}"
assert len(mcps) >= 25, f"mcps={len(mcps)}"
browser_n = sum(1 for m in mcps if m["category"] == "Browser Automation")
design_n = sum(1 for m in mcps if m["category"] == "Design")
assert browser_n >= 3, f"browser={browser_n}"
assert design_n >= 2, f"design={design_n}"

CAT.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"skills={len(skills)} mcps={len(mcps)} browser={browser_n} design={design_n}")
print(f"wrote {CAT}")
