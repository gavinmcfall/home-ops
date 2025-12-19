#!/usr/bin/env python3
"""Interactive PR management tool for Renovate PRs."""

import subprocess
import json
import re
import time
from collections import defaultdict
from datetime import datetime
from zoneinfo import ZoneInfo

REPO = "gavinmcfall/home-ops"
BOT_AUTHOR = "nerdz-bot[bot]"
REBASE_LABEL = "renovate/force-rebase"
TIMEZONE = ZoneInfo("Pacific/Auckland")
WATCH_TIMEOUT_SECONDS = 600  # 10 minutes
WATCH_POLL_INTERVAL = 10  # seconds

# Containers to skip (won't be auto-merged)
DONT_TOUCH = [
    "itzg/minecraft-server",
    "minecraft",
    "ghcr.io/immich-app/immich-server",
    "ghcr.io/immich-app/immich-machine-learning",
    "ingress-nginx",
]


def format_nz_timestamp(iso_timestamp: str) -> str:
    """Convert ISO timestamp to NZ format: YYYY-MMM-DD HH:MM AM/PM."""
    if not iso_timestamp:
        return "N/A"
    dt = datetime.fromisoformat(iso_timestamp.replace("Z", "+00:00"))
    nz_dt = dt.astimezone(TIMEZONE)
    return nz_dt.strftime("%Y-%b-%d %I:%M %p")


def run_gh(cmd: list[str]) -> dict | list | None:
    """Run a gh CLI command and return parsed JSON output."""
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running {' '.join(cmd)}:\n{result.stderr}")
        return None
    if not result.stdout.strip():
        return None
    return json.loads(result.stdout)


def fetch_prs() -> list[dict]:
    """Fetch all open PRs from the bot author."""
    prs = run_gh([
        "gh", "pr", "list",
        "--repo", REPO,
        "--author", BOT_AUTHOR,
        "--state", "open",
        "--json", "number,title,body,updatedAt,labels",
        "--limit", "1000"
    ])
    return prs if prs else []


def parse_renovate_body(body: str) -> list[tuple[str, str]]:
    """Parse update info from Renovate PR body."""
    updates = []
    if not body or "This PR contains the following updates" not in body:
        return updates

    pattern = r"\|\s*(?:\[(.*?)\]\(.*?\)|(.*?))\s*\|\s*(major|minor|patch|digest)\s*\|\s*`([^`]*)`\s*->\s*`([^`]*)`\s*\|"
    matches = re.findall(pattern, body)

    for match in matches:
        name = match[0] if match[0] else match[1]
        change_type = match[2]
        updates.append((name.strip(), change_type.strip().lower()))

    return updates


def classify_update(body: str, title: str, labels: list[dict]) -> str:
    """Classify a PR as digest, patch, minor, major, or unknown."""
    updates = parse_renovate_body(body)
    if updates:
        return updates[0][1]

    # Fallback: Check for digest (SHA format)
    if re.search(r"\b[0-9a-f]{7,}\b", title):
        return "digest"

    # Fallback: keyword match
    if match := re.search(r"\b(major|minor|patch)\b", title, re.IGNORECASE):
        return match.group(1).lower()

    # Fallback: Check labels for type/patch, type/minor, etc.
    for label in labels:
        label_name = label.get("name", "").lower()
        if label_name == "type/digest":
            return "digest"
        if label_name == "type/patch":
            return "patch"
        if label_name == "type/minor":
            return "minor"
        if label_name == "type/major":
            return "major"

    return "unknown"


def is_dont_touch(pr_title: str) -> bool:
    """Check if PR should be in dont_touch category."""
    normalized = pr_title.lower()
    return any(skip.lower() in normalized for skip in DONT_TOUCH)


def group_prs(prs: list[dict]) -> dict[str, list[dict]]:
    """Group PRs by update type."""
    grouped = defaultdict(list)

    for pr in prs:
        update_type = classify_update(pr.get("body", ""), pr["title"], pr.get("labels", []))
        if is_dont_touch(pr["title"]):
            update_type = "dont_touch"
        grouped[update_type].append(pr)

    return grouped


def display_prs(grouped: dict[str, list[dict]]) -> dict[int, dict]:
    """Display PRs grouped by category and return numbered lookup."""
    numbered = {}
    counter = 1
    categories = ["dont_touch", "digest", "patch", "minor", "major", "unknown"]

    for category in categories:
        prs = grouped.get(category, [])
        if not prs:
            continue

        print(f"\n🧩 {category.upper()} UPDATES ({len(prs)})")
        print("-" * 70)

        for pr in prs:
            timestamp = format_nz_timestamp(pr.get("updatedAt", ""))
            title = pr["title"][:45] + "..." if len(pr["title"]) > 48 else pr["title"]
            has_rebase_label = any(
                l.get("name") == REBASE_LABEL for l in pr.get("labels", [])
            )
            rebase_indicator = " [R]" if has_rebase_label else ""

            print(f"  {counter:3}. PR #{pr['number']}: {title:<48} │ {timestamp}{rebase_indicator}")
            numbered[counter] = pr
            numbered[counter]["category"] = category
            counter += 1

    return numbered


def add_rebase_label(pr_number: int) -> bool:
    """Add the rebase label to a PR using REST API."""
    payload = json.dumps({"labels": [REBASE_LABEL]})
    result = subprocess.run(
        ["gh", "api", f"repos/{REPO}/issues/{pr_number}/labels",
         "--method", "POST", "--input", "-", "--silent"],
        input=payload,
        capture_output=True,
        text=True
    )
    return result.returncode == 0


def trigger_renovate_workflow() -> bool:
    """Trigger the Renovate GitHub Action workflow."""
    result = subprocess.run(
        ["gh", "workflow", "run", "renovate.yaml", "--repo", REPO],
        capture_output=True,
        text=True
    )
    return result.returncode == 0


def merge_pr(pr_number: int) -> bool:
    """Merge a PR."""
    result = subprocess.run(
        ["gh", "pr", "merge", str(pr_number), "--repo", REPO, "--merge"],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"  Error merging PR #{pr_number}: {result.stderr.strip()}")
        return False
    return True


def extract_app_name(pr_title: str) -> str | None:
    """Extract app name from PR title.

    Examples:
    - 'fix(radarr): update image...' -> 'radarr'
    - 'fix(helm): update chart plane-ce...' -> 'plane-ce'
    - 'fix(container): update image ghcr.io/onedr0p/sonarr...' -> 'sonarr'
    """
    # Pattern 1: fix(app-name): ...
    if match := re.match(r"^\w+\(([^)]+)\):", pr_title):
        scope = match.group(1)
        # If scope is generic (helm, container, github-action), try to get app from rest
        if scope in ("helm", "container", "github-action"):
            # Try to extract from 'update chart APP-NAME' or 'update image .../APP'
            if chart_match := re.search(r"update chart (\S+)", pr_title):
                return chart_match.group(1).lower()
            if image_match := re.search(r"/([^/:@\s]+)(?::|@|\s|$)", pr_title):
                return image_match.group(1).lower()
        else:
            return scope.lower()

    return None


def run_kubectl(args: list[str]) -> tuple[bool, str]:
    """Run kubectl command and return (success, output)."""
    result = subprocess.run(
        ["kubectl"] + args,
        capture_output=True,
        text=True
    )
    return result.returncode == 0, result.stdout + result.stderr


def get_helmreleases_for_app(app_name: str) -> list[dict]:
    """Get all HelmReleases matching an app name across all namespaces.

    Matches HelmReleases that:
    - Exactly match the app name (radarr -> radarr)
    - Start with the app name followed by a hyphen (radarr -> radarr-uhd)

    This handles cases like radarr/radarr-uhd, sonarr/sonarr-uhd/sonarr-foreign.
    """
    success, output = run_kubectl([
        "get", "helmrelease", "-A",
        "-o", "json"
    ])
    if not success:
        return []

    results = []
    try:
        data = json.loads(output)
        for hr in data.get("items", []):
            name = hr.get("metadata", {}).get("name", "")
            name_lower = name.lower()
            app_lower = app_name.lower()

            # Match exact name or name starting with app-
            if name_lower == app_lower or name_lower.startswith(f"{app_lower}-"):
                conditions = hr.get("status", {}).get("conditions", [])
                ready_condition = next(
                    (c for c in conditions if c.get("type") == "Ready"),
                    None
                )
                results.append({
                    "name": name,
                    "namespace": hr.get("metadata", {}).get("namespace", ""),
                    "ready": ready_condition.get("status") == "True" if ready_condition else False,
                    "message": ready_condition.get("message", "") if ready_condition else "",
                    "reason": ready_condition.get("reason", "") if ready_condition else "",
                })
    except json.JSONDecodeError:
        pass

    return results


def get_deployment_status(app_name: str, namespace: str) -> dict | None:
    """Get Deployment/StatefulSet pod status for an app."""
    # Try deployment first
    for kind in ["deployment", "statefulset"]:
        success, output = run_kubectl([
            "get", kind, "-n", namespace,
            "-o", "json"
        ])
        if not success:
            continue

        try:
            data = json.loads(output)
            for item in data.get("items", []):
                name = item.get("metadata", {}).get("name", "")
                if app_name.lower() in name.lower():
                    status = item.get("status", {})
                    replicas = status.get("replicas", 0)
                    ready = status.get("readyReplicas", 0)
                    return {
                        "name": name,
                        "kind": kind,
                        "replicas": replicas,
                        "ready": ready,
                        "all_ready": replicas > 0 and replicas == ready,
                    }
        except json.JSONDecodeError:
            pass

    return None


def watch_deployments(app_names: list[str]) -> None:
    """Watch HelmReleases and Deployments until all are healthy or timeout."""
    if not app_names:
        return

    # Deduplicate and filter None
    base_apps = list(set(a for a in app_names if a))
    if not base_apps:
        print("\nNo app names could be extracted from PRs")
        return

    # Discover all HelmReleases matching these apps (e.g., radarr -> radarr, radarr-uhd)
    print(f"\n🔍 Discovering HelmReleases for: {', '.join(base_apps)}")
    hr_to_watch: dict[str, dict] = {}  # hr_name -> {namespace, base_app}

    for app in base_apps:
        hrs = get_helmreleases_for_app(app)
        for hr in hrs:
            hr_to_watch[hr["name"]] = {
                "namespace": hr["namespace"],
                "base_app": app,
            }

    if not hr_to_watch:
        print("No matching HelmReleases found in cluster")
        return

    print(f"\n📡 Watching {len(hr_to_watch)} HelmRelease(s) for reconciliation...")
    print(f"   Timeout: {WATCH_TIMEOUT_SECONDS // 60} minutes")
    print(f"   HelmReleases: {', '.join(sorted(hr_to_watch.keys()))}")
    print("-" * 70)

    # Track status for each HelmRelease
    hr_status = {
        hr_name: {"hr_ready": False, "pods_ready": False, "namespace": info["namespace"]}
        for hr_name, info in hr_to_watch.items()
    }
    start_time = time.time()

    while True:
        elapsed = time.time() - start_time
        if elapsed > WATCH_TIMEOUT_SECONDS:
            print(f"\n⏱️  Timeout reached ({WATCH_TIMEOUT_SECONDS // 60} minutes)")
            break

        all_healthy = True
        timestamp = format_nz_timestamp(datetime.now(TIMEZONE).isoformat())

        print(f"\n[{timestamp}] Checking status...")

        for hr_name, info in hr_to_watch.items():
            # Get fresh status for this specific HelmRelease
            hrs = get_helmreleases_for_app(hr_name)
            hr = next((h for h in hrs if h["name"] == hr_name), None)

            if hr:
                hr_status[hr_name]["hr_ready"] = hr["ready"]

                # Check pods
                deploy = get_deployment_status(hr_name, info["namespace"])
                if deploy:
                    hr_status[hr_name]["pods_ready"] = deploy["all_ready"]
                    pods_str = f"{deploy['ready']}/{deploy['replicas']} pods"
                else:
                    # Some HRs might not have a deployment (e.g., CronJobs)
                    hr_status[hr_name]["pods_ready"] = hr["ready"]
                    pods_str = "no deployment"

                hr_icon = "✓" if hr["ready"] else "⏳"
                pods_icon = "✓" if hr_status[hr_name]["pods_ready"] else "⏳"

                status_line = f"  {hr_name:<25} HR: {hr_icon}  Pods: {pods_icon} ({pods_str})"
                if not hr["ready"] and hr["message"]:
                    status_line += f"\n                              └─ {hr['message'][:55]}"
                print(status_line)

                if not (hr["ready"] and hr_status[hr_name]["pods_ready"]):
                    all_healthy = False
            else:
                print(f"  {hr_name:<25} HelmRelease not found")
                all_healthy = False

        if all_healthy:
            print(f"\n✅ All {len(hr_to_watch)} HelmRelease(s) healthy!")
            break

        # Show countdown
        remaining = WATCH_TIMEOUT_SECONDS - int(elapsed)
        print(f"\n  ⏳ {remaining}s remaining... (polling every {WATCH_POLL_INTERVAL}s)")
        time.sleep(WATCH_POLL_INTERVAL)

    # Final summary
    print("\n" + "=" * 70)
    print("Final Status:")
    healthy_count = sum(1 for s in hr_status.values() if s["hr_ready"] and s["pods_ready"])
    print(f"  {healthy_count}/{len(hr_to_watch)} HelmReleases healthy")

    failed = [hr for hr, s in hr_status.items() if not (s["hr_ready"] and s["pods_ready"])]
    if failed:
        print(f"  Failed/Pending: {', '.join(failed)}")


def rebase_menu(numbered: dict[int, dict], grouped: dict[str, list[dict]]) -> None:
    """Handle rebase submenu."""
    print("\nRebase options:")
    print("  [number] Single PR by list number")
    print("  [d] All DIGEST PRs")
    print("  [p] All PATCH PRs")
    print("  [n] All MINOR PRs")
    print("  [j] All MAJOR PRs")
    print("  [a] ALL Renovate PRs")
    print("  [b] Back")

    choice = input("\n> ").strip().lower()

    if choice == "b":
        return

    prs_to_rebase = []

    if choice == "d":
        prs_to_rebase = grouped.get("digest", [])
    elif choice == "p":
        prs_to_rebase = grouped.get("patch", [])
    elif choice == "n":
        prs_to_rebase = grouped.get("minor", [])
    elif choice == "j":
        prs_to_rebase = grouped.get("major", [])
    elif choice == "a":
        for cat in ["digest", "patch", "minor", "major", "unknown"]:
            prs_to_rebase.extend(grouped.get(cat, []))
    elif choice.isdigit():
        num = int(choice)
        if num in numbered:
            prs_to_rebase = [numbered[num]]
        else:
            print(f"Invalid PR number: {num}")
            return
    else:
        print("Invalid choice")
        return

    if not prs_to_rebase:
        print("No PRs to rebase in that category")
        return

    print(f"\nAdding rebase label to {len(prs_to_rebase)} PR(s)...")
    success_count = 0
    for pr in prs_to_rebase:
        if add_rebase_label(pr["number"]):
            print(f"  ✓ PR #{pr['number']}")
            success_count += 1
        else:
            print(f"  ✗ PR #{pr['number']} - failed")

    if success_count > 0:
        print("\nTriggering Renovate workflow...")
        if trigger_renovate_workflow():
            print("  ✓ Workflow triggered")
        else:
            print("  ✗ Failed to trigger workflow")

    print(f"\nLabeled {success_count}/{len(prs_to_rebase)} PRs")
    print("Use [s] to check rebase status after a few minutes")


def merge_menu(numbered: dict[int, dict], grouped: dict[str, list[dict]]) -> None:
    """Handle merge submenu."""
    print("\nMerge options:")
    print("  [number] Single PR by list number")
    print("  [d] All DIGEST PRs")
    print("  [p] All PATCH PRs")
    print("  [n] All MINOR PRs")
    print("  [b] Back")

    choice = input("\n> ").strip().lower()

    if choice == "b":
        return

    prs_to_merge = []

    if choice == "d":
        prs_to_merge = grouped.get("digest", [])
    elif choice == "p":
        prs_to_merge = grouped.get("patch", [])
    elif choice == "n":
        prs_to_merge = grouped.get("minor", [])
    elif choice.isdigit():
        num = int(choice)
        if num in numbered:
            prs_to_merge = [numbered[num]]
        else:
            print(f"Invalid PR number: {num}")
            return
    else:
        print("Invalid choice")
        return

    if not prs_to_merge:
        print("No PRs to merge in that category")
        return

    # Confirmation for bulk merge
    if len(prs_to_merge) > 1:
        confirm = input(f"Merge {len(prs_to_merge)} PRs? (y/n): ").strip().lower()
        if confirm != "y":
            print("Cancelled")
            return

    # Extract app names before merging
    app_names = [extract_app_name(pr["title"]) for pr in prs_to_merge]

    print(f"\nMerging {len(prs_to_merge)} PR(s)...")
    merged_apps = []
    success_count = 0
    for i, pr in enumerate(prs_to_merge):
        print(f"  Merging PR #{pr['number']}...", end=" ")
        if merge_pr(pr["number"]):
            print("✓")
            success_count += 1
            if app_names[i]:
                merged_apps.append(app_names[i])
        else:
            print("✗")

    print(f"\nMerged {success_count}/{len(prs_to_merge)} PRs")

    # Ask if user wants to watch deployments
    if merged_apps:
        watch = input(f"\nWatch {len(merged_apps)} app(s) for reconciliation? (y/n): ").strip().lower()
        if watch == "y":
            watch_deployments(merged_apps)


def main() -> None:
    """Main interactive loop."""
    print("Fetching PRs...")
    prs = fetch_prs()

    if not prs:
        print("No open Renovate PRs found")
        return

    grouped = group_prs(prs)
    numbered = display_prs(grouped)

    while True:
        print("\nActions:")
        print("  [r] Rebase PRs")
        print("  [m] Merge PRs")
        print("  [s] Check rebase status (refresh)")
        print("  [q] Quit")

        choice = input("\n> ").strip().lower()

        if choice == "q":
            break
        elif choice == "r":
            rebase_menu(numbered, grouped)
        elif choice == "m":
            merge_menu(numbered, grouped)
        elif choice == "s":
            print("\nRefreshing PR list...")
            prs = fetch_prs()
            if prs:
                grouped = group_prs(prs)
                numbered = display_prs(grouped)
            else:
                print("No open Renovate PRs found")
        else:
            print("Invalid choice")


if __name__ == "__main__":
    main()
