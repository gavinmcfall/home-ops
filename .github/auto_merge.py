import os
from github import Github

# Retrieve the GitHub token from the environment variable
GITHUB_TOKEN = os.getenv("GITHUB_PAT")
REPO_NAME = "gavinmcfall/home-ops"

if not GITHUB_TOKEN:
    raise ValueError("Please set the GITHUB_PAT environment variable.")

def auto_merge_minor_patch_prs():
    g = Github(GITHUB_TOKEN)
    repo = g.get_repo(REPO_NAME)
    
    pr_count = 0
    open_prs = repo.get_pulls(state="open", sort="created", direction="desc")
    
    for pr in open_prs:
        print(f"Checking PR #{pr.number}: {pr.title}")
        try:
            comments = pr.get_issue_comments()
            for comment in comments:
                print(f"  Comment: {comment.body}")
                if "minor" in comment.body.lower() or "patch" in comment.body.lower():
                    print(f"Merging PR #{pr.number}: {pr.title}")
                    pr.merge()
                    pr_count += 1
                    break
        except Exception as e:
            print(f"Error processing PR #{pr.number}: {e}")
    
    print(f"Processed {pr_count} PR(s).")

if __name__ == "__main__":
    auto_merge_minor_patch_prs()
