## Release Ztabby

Follow these steps exactly to release a new version of Ztabby.

### Step 1: Analyze Changes

Run `git log $(git describe --tags --abbrev=0)..HEAD --oneline` to see all commits since the last release. If no tags exist, use `git log --oneline -20`.

Categorize changes into: new features, improvements, bug fixes.

Recommend a semver bump (patch/minor/major) with clear reasoning based on the changes:
- **patch**: bug fixes, small improvements
- **minor**: new user-facing features, significant UX changes
- **major**: breaking changes, major rewrites

Present the recommendation and ask the user to confirm or override. Do NOT proceed until confirmed.

### Step 2: Generate Release Notes

From the categorized commits, write user-facing release notes. Rules:
- Write in a friendly tone focused on what the user can now do or how their experience improved
- Do NOT use raw commit messages — rewrite them as benefits
- Group related commits into single bullet points
- Format:
  ```
  ## What's new in Ztabby vX.Y.Z

  - **Feature name** — What the user can now do, in plain language.
  - **Improvement** — How the experience got better.
  - **Fix** — What no longer happens / what works correctly now.
  ```

Present the notes and ask the user to approve or edit. Do NOT proceed until approved.

### Step 3: Bump Version

Update the version string in `package.json` — the `"version": "X.Y.Z"` field.

### Step 4: Build & Test Locally

Build the debug configuration to validate:

```bash
xcodebuild -workspace ztabby.xcworkspace -scheme Debug -configuration Debug -derivedDataPath DerivedData build 2>&1 | grep -E "BUILD|error:" | head -10
```

If the build fails, stop and report the error. Do NOT continue.

If the build succeeds, kill any running Ztabby and launch the debug build:
```bash
pkill -f Ztabby; sleep 1 && open DerivedData/Build/Products/Debug/Ztabby-Debug.app
```

Ask the user to confirm it works before proceeding.

### Step 5: Commit, Tag, Push

```bash
git add package.json
git commit -m "Bump version to X.Y.Z"
git tag vX.Y.Z
git push && git push --tags
```

### Step 6: Create GitHub Release

Create a draft GitHub release with the friendly notes and installation instructions:

```bash
gh release create vX.Y.Z --draft --title "Ztabby vX.Y.Z" --notes "$(cat <<'NOTES'
## What's new in Ztabby vX.Y.Z

{the approved release notes from step 2}

---

### Installation
Download the `.zip` file, extract, and drag Ztabby to Applications.
Grant Accessibility permission when prompted.

### Requirements
- macOS 13+
NOTES
)"
```

### Step 7: Report

Show a summary:
- Version released
- Release notes
- Link to the GitHub Actions run (find it via `gh run list --workflow=release.yml --limit=1`)
- Link to the draft release
