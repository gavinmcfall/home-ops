import subprocess
import json
import re
from collections import defaultdict

REPO = "gavinmcfall/home-ops"

# Define containers you want to skip touching
DONT_TOUCH = [
    "itzg/minecraft-server",
    "minecraft",
    "ghcr.io/immich-app/immich-server",
    "ghcr.io/immich-app/immich-machine-learning",
]

# Debug toggle
DEBUG = False

def debug(msg):
    if DEBUG:
        print(f"Debug: {msg}")

def run_gh(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running {' '.join(cmd)}:\n{result.stderr}")
        return None
    return json.loads(result.stdout)

def parse_renovate_body(body):
    updates = []
    if "This PR contains the following updates" not in body:
        debug("No update table found in PR body")
        return updates

    # This matches markdown table like:
    # | [ghcr.io/dragonflydb/dragonfly](https://redirect.github.com/dragonflydb/dragonfly) | minor | `v1.26.2` -> `v1.28.0` |
    # or
    # | ghcr.io/dragonflydb/dragonfly | minor | `v1.26.2` -> `v1.28.0` |
    pattern = r"\|\s*(?:\[(.*?)\]\(.*?\)|(.*?))\s*\|\s*(major|minor|patch|digest)\s*\|\s*`([^`]*)`\s*->\s*`([^`]*)`\s*\|"
    matches = re.findall(pattern, body)
    if not matches:
        debug("No matches found in PR body")
        return updates

    for match in matches:
        name = match[0] if match[0] else match[1]  # Handle both formats
        change_type = match[2]
        updates.append((name.strip(), change_type.strip().lower()))
        debug(f"Found update in PR body: {name} -> {change_type}")

    return updates

def classify_update(body, title):
    # First, try to parse the update type from the PR body
    updates = parse_renovate_body(body)
    if updates:
        debug(f"Found updates in body for PR: {title}")
        return updates[0][1]  # Return the first update type found in the body

    # Fallback: Check if title contains a short SHA format (7+ hex digits)
    if re.search(r"\b[0-9a-f]{7,}\b", title):
        debug(f"Found digest update in PR: {title}")
        return "digest"

    # Fallback: Try to classify by keyword in the title
    if match := re.search(r"\b(major|minor|patch)\b", title, re.IGNORECASE):
        debug(f"Keyword match found in PR: {title}")
        return match.group(1).lower()

    debug(f"No classification match found for PR: {title}")
    return "unknown"

def is_dont_touch(pr_title):
    normalized = pr_title.lower()
    return any(skip.lower() in normalized for skip in DONT_TOUCH)

def main():
    grouped = defaultdict(list)

    prs = run_gh([
        "gh", "pr", "list", "--repo", REPO,
        "--state", "open", "--json", "number,title,body", "--limit", "1000"
    ])

    if not prs:
        print("No PRs found or error fetching.")
        return

    for pr in prs:
        pr_number = pr["number"]
        pr_title = pr["title"]
        pr_body = pr.get("body", "")

        update_type = classify_update(pr_body, pr_title)
        grouped[update_type].append((pr_number, pr_title))

    # Reclassify "Don't Touch" items
    for update_type in list(grouped.keys()):
        for pr in grouped[update_type][:]:
            if is_dont_touch(pr[1]):
                grouped[update_type].remove(pr)
                grouped["dont_touch"].append(pr)

    # Final output
    for category in ["dont_touch", "digest", "patch", "minor", "major", "unknown"]:
        updates = grouped.get(category, [])
        print(f"\n🧩 {category.upper()} UPDATES ({len(updates)})")
        print("-" * 60)
        for pr_number, pr_title in updates:
            print(f"🔧 PR #{pr_number}: {pr_title}")

if __name__ == "__main__":
    main()
