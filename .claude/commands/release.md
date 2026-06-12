## Release Ztabby

Follow these steps exactly to release a new version of Ztabby.

How the pipeline works: you bump the version, create a DRAFT GitHub release containing the release notes, then push the tag. The tag push triggers `.github/workflows/release.yml`, which builds a signed Release app on a macos-26 runner, notarizes a DMG, Sparkle-signs it (SPARKLE_ED_PRIVATE_KEY secret; keypair also in the login Keychain as "Private key for signing Sparkle updates"), uploads it to your draft, publishes the release, and updates `docs/index.html` (homepage version + download link) and `docs/appcast.xml` (Sparkle auto-update feed) on main — which triggers the GitHub Pages deploy. Do NOT edit `docs/index.html` or `docs/appcast.xml` manually; the workflow owns them.

### Step 1: Analyze Changes

The current released version is in `package.json`. List commits since its tag:

```bash
git log "v$(node -p "require('./package.json').version")"..HEAD --oneline
```

(Do not use `git describe` — this repo carries hundreds of inherited upstream AltTab tags like `v6.x`/`v10.x` that don't belong to Ztabby's versioning.)

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

Update the `"version": "X.Y.Z"` field in `package.json`. That is the ONLY file to touch:
- `Info.plist` uses `#VERSION#` placeholders that the release workflow stamps at build time. Do NOT replace them locally.
- `docs/index.html` is updated by the workflow's `update-homepage` job after the release is published. Do NOT edit it here — editing it before the DMG exists publishes a dead download link.

### Step 4: Build & Test Locally

Build the debug configuration to validate. If `xcode-select -p` points at CommandLineTools, prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```bash
xcodebuild -workspace ztabby.xcworkspace -scheme Debug -configuration Debug -derivedDataPath DerivedData build 2>&1 | grep -E "BUILD|error:" | head -10
```

If the build fails, stop and report the error. Do NOT continue.

If the build succeeds, kill any running Ztabby and launch the debug build:
```bash
pkill -f Ztabby; sleep 1 && open DerivedData/Build/Products/Debug/Ztabby-Debug.app
```

Ask the user to confirm it works before proceeding.

### Step 5: Commit and Push the Version Bump

```bash
git add package.json
git commit -m "Bump version to X.Y.Z"
git tag vX.Y.Z
git push
```

Do NOT push the tag yet — the draft release with notes must exist first, so the workflow can attach the DMG to it instead of creating a notes-less release.

### Step 6: Create Draft Release, Then Push the Tag

Create the draft with the approved notes:

```bash
gh release create vX.Y.Z --draft --target main --title "Ztabby vX.Y.Z" --notes "$(cat <<'NOTES'
## What's new in Ztabby vX.Y.Z

{the approved release notes from step 2}

---

### Installation
Download the `.dmg` file, open it, and drag Ztabby to Applications.
Grant Accessibility permission when prompted.

### Requirements
- macOS 13+ (Apple Silicon)
NOTES
)"
```

Then trigger the release build:

```bash
git push --tags
```

### Step 7: Watch the Workflow and Report

Find the run with `gh run list --workflow=release.yml --limit=1` and watch it with `gh run watch <run-id>` (it builds, signs, notarizes — expect ~10-15 minutes). If it fails, fetch the error with `gh run view <run-id> --log-failed` and report it.

On success, verify and report:
- `gh release view vX.Y.Z` shows the release is published (not draft) with the DMG attached
- `git pull` shows the `update-homepage` commit, and `docs/index.html` references vX.Y.Z
- Show the version, the release notes, the release URL, and the Actions run URL
