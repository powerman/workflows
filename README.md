# Reusable workflows for GitHub Actions

## Release PR

Release PR is a tool for simplifying and automating the release process of third-party
projects on GitHub. It's designed for use in GitHub Actions within a project's release
workflow and provides reusable workflows.

### Overview

Release PR provides automated release management with visual control over releases. The
system automatically creates and maintains a "release PR" that shows exactly what version will
be released and what changes will be included.

#### Key Features

- **Visual Release Control**: Release PR shows the exact version and changelog before release.
- **One-Click Releases**: Release by merging the release PR.
- **Automatic Version Bumping**: Uses git-cliff with semantic versioning.
- **Manual Version Override**: Edit PR title to set custom version.
- **Race Condition Handling**: Prevents incorrect releases when conflicts occur.
- **Draft Release Creation**: Creates GitHub releases with a proper changelog.

#### How It Works

1. **Auto PR Creation**: When commits are pushed to the main branch, a "release PR" is
   automatically created or updated.
2. **Version Display**: PR title shows the next release version (calculated by git-cliff or
   manually set).
3. **Changelog Preview**: PR description contains the full changelog for the upcoming release.
4. **Manual Version Control**: Edit the PR title to override the version; the changelog updates
   automatically.
5. **Release**: Merge the PR to create a new release.
6. **Race Condition Protection**: If changes occur during merge, a new PR is created instead
   of releasing.

### Project Requirements

1. **Single project per repository**: No monorepo support.
2. **CHANGELOG.md**: Must be in repository root, managed by `git-cliff`.
3. **git-cliff configuration**: Proper `cliff.toml` configuration required. If this file
   is not present in the repository root, a [default configuration] will be used.
4. **Semantic versioning**: Project must use semver for releases.
5. **Auto version bump managed by git-cliff**: Project must use (mostly) conventional commits.
6. **Git tags**: Releases must be tagged with version numbers.
7. **Repository permissions**: Actions must be allowed to create PRs.

### Quick Start

#### 1. Set Required Repository Settings

In **Settings → Actions → General**:

- ✅ **Allow GitHub Actions to create and approve pull requests**

#### 2. Add `RELEASE_TOKEN` (Optional)

By default, Release PR workflow uses the built-in `GITHUB_TOKEN` secret.
From GitHub's [docs][github-trigger-workflow]:

> When you use the repository's `GITHUB_TOKEN` to perform tasks,
> events triggered by the `GITHUB_TOKEN` will not create a new workflow run.
> This prevents you from accidentally creating recursive workflow runs.

This can be a problem if you have branch protection
rules that require certain checks (i.e. other workflows) to pass before merging.

To solve this, you can provide an alternative token for release workflow.

1.  Create a [Fine-grained personal access token][create-PAT]
    with **Repository access** set to either "All repositories" or "Only select repositories"
    and **Repository permissions** "Contents" and "Pull requests" both set to "Read and write".
2.  Add this token as a repository secret named `RELEASE_TOKEN` in
    **Settings → Secrets and variables → Actions**.
3.  In your workflow, pass the `RELEASE_TOKEN` to the `release-pr.yml` workflow via the `TOKEN`
    secret. If you have other jobs that need this token, you can set a workflow-level
    `env` variable for convenience. See the examples below.

#### 3. Create Release Workflow

Create `.github/workflows/release.yml` in your project:

```yaml
name: Release

on:
  push: # To create/update release PR and to make a release.
  pull_request: # To update release PR after manually changing version for the next release.
    types: [edited]

permissions:
  contents: write # To create/update release_pr branch, create a release and a tag.
  pull-requests: write # To create/update PR from release_pr branch.

env:
  GITHUB_TOKEN: ${{ secrets.RELEASE_TOKEN || secrets.GITHUB_TOKEN }}

jobs:
  release-pr:
    uses: powerman/workflows/.github/workflows/release-pr.yml@main
    # with:
    #   target_branch: 'main'                 # Default: repository default branch
    #   pr_branch: 'release-pr'               # Default: 'release-pr'
    #   commit_prefix: 'chore: release'       # Default: 'chore: release'
    #   version_cmd: 'echo "$RELEASE_PR_VERSION" >.my-version'  # Optional
    secrets:
      TOKEN: ${{ secrets.RELEASE_TOKEN }}

  # Mark release as non-draft and latest.
  finalize:
    needs: [release-pr]
    if: ${{ needs.release-pr.outputs.result == 'released' }}
    permissions:
      contents: write # To update the GitHub release.
    timeout-minutes: 5
    runs-on: ubuntu-latest
    steps:
      - name: Publish release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ needs.release-pr.outputs.version }}
          body: ${{ needs.release-pr.outputs.changelog }}
          draft: false
          make_latest: true
          token: ${{ env.GITHUB_TOKEN }}
```

#### 4. Configure Changelog

Create `cliff.toml` in your project root.
See the [git-cliff documentation][git-cliff-conf] for configuration details.

It is recommended to use <https://github.com/powerman/workflows/blob/main/cliff.toml>
as an example/starting point. There are a couple of places which mention 'chore: release' and
these are important to keep or handle in a similar way in your config too - contents of
`CHANGELOG.md` should not change because of these commits.

#### 5. Push Or Merge To Release Branch

Release PR should be opened automatically.

### Workflow Reference: `release-pr.yml`

**Inputs:**

- `commit_prefix` (optional): Commit message prefix (default: `'chore: release'`).
  - If you use a different prefix, you probably need to update it in `cliff.toml` too.
- `pr_branch` (optional): Technical branch name (default: `'release-pr'`).
  - **Single commit**: Release branch contains only one commit with `CHANGELOG.md` update
    and optional version-related updates in other files.
  - **Force push**: Branch is force-pushed on updates to maintain single commit
- `target_branch` (optional): Target branch for releases (default: repository default branch).
- `version_cmd` (optional): Shell command to update additional files with the version.
  - **Working directory**: Clean state on `inputs.pr_branch` branch.
  - **Timing**: Before `CHANGELOG.md` generation, `git add .` and commit.
  - **Environment variable**: `$RELEASE_PR_VERSION` contains full version (e.g., "v1.2.3").

**Outputs:**

- `result`: Action taken - `'prepared-pr'`, `'set-version'`, `'released'`, or empty.
- `version`: Version that was processed.
- `changelog`: Changelog for the version.

**Secrets:**

- `TOKEN`: Token to use for authentication. Optional, uses `GITHUB_TOKEN` by default.

**Triggers:**

- **Push to target branch**: Creates/updates release PR or performs release.
- **PR edited on release branch**: Updates release PR with new version.

### Customization Examples

#### Adding Version Command

Update additional files when the version changes:

```yaml
jobs:
  release-pr:
    uses: powerman/workflows/.github/workflows/release-pr.yml@main
    with:
      version_cmd: |
        # Strip 'v' prefix from version and update the version in package files.
        sed -i "s/version = \".*\"/version = \"${RELEASE_PR_VERSION#v}\"/" Cargo.toml
        sed -i "s/__version__ = \".*\"/__version__ = \"${RELEASE_PR_VERSION#v}\"/" src/__init__.py
```

#### Complete Release Workflow with Build and Sign assets

```yaml
name: Release

on:
  push: # To create/update release PR and to make a release.
  pull_request: # To update release PR after manually changing version for the next release.
    types: [edited]

permissions:
  contents: write # To create/update release_pr branch, create a release and a tag.
  pull-requests: write # To create/update PR from release_pr branch.
  id-token: write # For cosign signing.

env:
  GITHUB_TOKEN: ${{ secrets.RELEASE_TOKEN || secrets.GITHUB_TOKEN }}

jobs:
  release-pr:
    uses: powerman/workflows/.github/workflows/release-pr.yml@main
    secrets:
      TOKEN: ${{ secrets.RELEASE_TOKEN }}

  build-and-upload:
    needs: [release-pr]
    if: ${{ needs.release-pr.outputs.result == 'released' }}
    permissions:
      contents: write # To upload to GitHub release
      id-token: write # For cosign signing
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ env.GITHUB_TOKEN }}

      - name: Build the project
        run: |
          # Your build commands here
          make build
          mkdir -p ./dist
          cp target/release/myapp ./dist/

      - name: Sign assets
        uses: sigstore/cosign-installer@v3
      - run: |
          cd ./dist
          for file in *; do
            cosign sign-blob --yes "$file" --output-signature "${file}.sig"
          done

      - name: Upload to the release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ needs.release-pr.outputs.version }}
          body: ${{ needs.release-pr.outputs.changelog }}
          files: ./dist/*
          draft: false
          make_latest: true
          token: ${{ env.GITHUB_TOKEN }}
```

### How to Manage Changelog

The content of `CHANGELOG.md` is generated by `git-cliff` and can be controlled in several ways:

- **Set the next release version manually**: Edit the title of the release PR.
- **Add custom text for a specific version**: Modify the `body` template in `cliff.toml`.
  This can be used to customize the description for the current release (before it's published)
  or to add release notes for past releases that were missed in commit messages.
- **Add new entries to the current release**: Create an empty commit with a descriptive message
  using `git commit --allow-empty -m "..."`.
- **Modify existing entries**: Use `commit_preprocessors` in `cliff.toml` to fix typos
  across all commit messages or `postprocessors` to alter a specific commit.
- **Remove a commit from the changelog**: Add the commit hash to a `.cliffignore` file.
- **Filter commit types**: Selectively include only significant commit types in the changelog
  by configuring `commit_parsers` to group commits and then filtering these groups
  within the `body` template in `cliff.toml`.

### Race Condition Handling

Release PR automatically handles race conditions where:

1. **Manual version change + new commits**: User changes version in PR title while new commits
   are being pushed
2. **Delayed workflow execution**: Release PR is merged before the latest changes are
   reflected

**How it works**:

- During release, the system regenerates CHANGELOG.md with the target version
- If the generated changelog differs from the current state, a race condition is detected
- Instead of proceeding with potentially incorrect release, a new release PR is created
- This ensures users always see the exact changes that will be released

### Comparison with Alternatives

Release PR fills a unique niche in the automated release ecosystem:
it is **simple**, **reliable** and **language agnostic**.
It does just one thing and does it well!
Here's how it compares to other popular solutions:

#### 📊 Feature Comparison

| Feature                     | **Release PR**        | **Google Release Please** | **Rust release-pr**    |
| --------------------------- | --------------------- | ------------------------- | ---------------------- |
| **Target Languages**        | Any (via version_cmd) | 20+ languages built-in    | Rust only              |
| **Setup Complexity**        | Minimal               | High                      | Medium                 |
| **Architecture**            | 4 workflows, ~650 LOC | Complex, many configs     | Rust binary + Action   |
| **Monorepo Support**        | ❌                    | ✅ Excellent              | ✅ Workspace support   |
| **Registry Publishing**     | ❌ (external job)     | ✅ Built-in               | ✅ crates.io           |
| **Manual Version Override** | ✅ Edit PR title      | ✅ Complex config         | ✅ PR commands         |
| **Race Condition Handling** | ✅ Automatic          | ⚠️ Issues reported        | ✅ Concurrency control |
| **Zero-config Setup**       | ✅ Nearly             | ❌ Complex                | ✅ Yes                 |

[git-cliff-conf]: https://git-cliff.org/docs/configuration
[github-trigger-workflow]: https://docs.github.com/en/actions/using-workflows/triggering-a-workflow#triggering-a-workflow-from-a-workflow
[create-PAT]: https://github.com/settings/personal-access-tokens
[default configuration]: https://github.com/powerman/workflows/blob/main/cliff.toml
