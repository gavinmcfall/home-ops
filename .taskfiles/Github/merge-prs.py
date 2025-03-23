import subprocess
import json
import time
from collections import defaultdict

def check_rate_limit():
    """
    Check the current GitHub API rate limit.
    """
    try:
        result = subprocess.run(["gh", "api", "rate_limit"], capture_output=True, text=True, check=True)
        rate_limit = json.loads(result.stdout)
        remaining = rate_limit["resources"]["core"]["remaining"]
        reset_time = rate_limit["resources"]["core"]["reset"]
        return remaining, reset_time
    except subprocess.CalledProcessError as e:
        print(f"Error checking rate limit: {e.stderr}")
        return None, None

def wait_for_rate_limit_reset(reset_time):
    """
    Wait until the rate limit resets.
    """
    current_time = int(time.time())
    if reset_time > current_time:
        wait_seconds = reset_time - current_time
        print(f"Rate limit exceeded. Waiting for {wait_seconds} seconds...")
        time.sleep(wait_seconds)

def run_pr_list():
    """
    Run pr-list.py and capture its output.
    """
    try:
        result = subprocess.run(["python3", "pr-list.py"], capture_output=True, text=True, check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error running pr-list.py: {e.stderr}")
        return None

def parse_pr_list_output(output):
    """
    Parse the output of pr-list.py into a dictionary of categories and PRs.
    """
    grouped = defaultdict(list)
    current_category = None

    for line in output.splitlines():
        if line.startswith("🧩"):
            # Extract the category name (e.g., "DIGEST UPDATES")
            current_category = line.split("🧩")[1].split("UPDATES")[0].strip().lower()
        elif line.startswith("🔧"):
            # Extract PR number and title
            pr_info = line.split("#")[1].strip()  # Remove the "🔧 PR" prefix
            pr_number = pr_info.split(":")[0].strip()  # PR number is before the first colon
            pr_title = ":".join(pr_info.split(":")[1:]).strip()  # Everything after the first colon is the title
            grouped[current_category].append((pr_number, pr_title))

    return grouped

def merge_pr(pr_number, dry_run=False):
    """
    Merge the PR using GitHub CLI.
    If dry_run is True, only simulate the merge.
    """
    if dry_run:
        print(f"[Dry Run] Would merge PR #{pr_number}")
        return

    # Check rate limit before merging
    remaining, reset_time = check_rate_limit()
    if remaining is not None and remaining <= 0:
        wait_for_rate_limit_reset(reset_time)

    print(f"Merging PR #{pr_number}...")
    try:
        result = subprocess.run(["gh", "pr", "merge", pr_number, "--merge"], capture_output=True, text=True, check=True)
        print(f"Successfully merged PR #{pr_number}!")
    except subprocess.CalledProcessError as e:
        print(f"Error merging PR #{pr_number}: {e.stderr}")
        if "Base branch was modified" in e.stderr:
            print(f"Conflict detected in PR #{pr_number}. Retrying after 5 seconds...")
            time.sleep(5)  # Wait before retrying
            merge_pr(pr_number)  # Retry the merge
        else:
            print(f"Skipping PR #{pr_number} due to an unrecoverable error.")

def merge_all_prs(prs, dry_run=False):
    """
    Merge all PRs in the given list.
    If dry_run is True, only simulate the merges.
    """
    for pr_number, pr_title in prs:
        merge_pr(pr_number, dry_run)

def main():
    """
    Main function to run the script.
    """
    # Store PRs in memory for recall
    pr_data = {}

    while True:
        # Run pr-list.py and parse its output
        print("Fetching PRs...")
        output = run_pr_list()
        if not output:
            return

        print(output)  # Show the output of pr-list.py

        # Parse the output into a dictionary of categories and PRs
        grouped = parse_pr_list_output(output)

        # Store the grouped PRs in memory
        pr_data = grouped

        # Ask the user if they want to merge PRs
        print("\nWhich PRs would you like to merge?")
        print("1: Digest")
        print("2: Patch")
        print("3: Minor")
        print("n: None")
        choice = input("Enter your choice (1/2/3/n): ").strip().lower()

        if choice == "n":
            print("No PRs will be merged. Exiting...")
            break
        elif choice in ["1", "2", "3"]:
            # Map the choice to the corresponding category
            category_map = {"1": "digest", "2": "patch", "3": "minor"}
            selected_category = category_map[choice]

            # Get the list of PRs for the selected category
            prs = pr_data.get(selected_category, [])
            if not prs:
                print(f"No PRs found in the '{selected_category}' category.")
                continue

            # Show the PRs in the selected category
            print(f"\nPRs in the '{selected_category}' category:")
            for i, (pr_number, pr_title) in enumerate(prs, start=1):
                print(f"{i}: PR #{pr_number}: {pr_title}")

            # Ask the user what action to take
            print("\nWhat would you like to do?")
            print("m: Merge a specific PR")
            print("a: Merge all PRs in this category")
            print("d: Dry run (simulate merging all)")
            print("b: Go back")
            action = input("Enter your choice (m/a/d/b): ").strip().lower()

            if action == "b":
                continue
            elif action == "m":
                # Ask the user to select a PR to merge
                pr_choice = input("Enter the number of the PR to merge: ").strip()
                try:
                    pr_index = int(pr_choice) - 1
                    if 0 <= pr_index < len(prs):
                        pr_number, pr_title = prs[pr_index]
                        merge_pr(pr_number)
                    else:
                        print("Invalid selection. Please try again.")
                except ValueError:
                    print("Invalid input. Please enter a number.")
            elif action == "a":
                # Merge all PRs in the selected category
                confirm = input(f"Are you sure you want to merge ALL {len(prs)} PRs in the '{selected_category}' category? (y/n): ").strip().lower()
                if confirm == "y":
                    merge_all_prs(prs)
                else:
                    print("Merge canceled.")
            elif action == "d":
                # Dry run: simulate merging all PRs
                print("\nDry run mode: No PRs will actually be merged.")
                merge_all_prs(prs, dry_run=True)
            else:
                print("Invalid choice. Please enter m, a, d, or b.")
        else:
            print("Invalid choice. Please enter 1, 2, 3, or n.")

if __name__ == "__main__":
    main()
