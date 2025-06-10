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

- **Visual Release Control**: Release PR shows the exact version and changelog before release
- **One-Click Releases**: Release by merging the release PR
- **Automatic Version Bumping**: Uses git-cliff with semantic versioning
- **Race Condition Handling**: Prevents incorrect releases when conflicts occur
- **Manual Version Override**: Edit PR title to set custom version
- **Draft Release Creation**: Creates GitHub releases with a proper changelog

#### How It Works

1. **Auto PR Creation**: When commits are pushed to the main branch, a "release PR" is
   automatically created or updated
2. **Version Display**: PR title shows the next release version (calculated by git-cliff or
   manually set)
3. **Changelog Preview**: PR description contains the full changelog for the upcoming release
4. **Manual Version Control**: Edit the PR title to override the version; the changelog updates
   automatically
5. **Release**: Merge the PR to create a new release
6. **Race Condition Protection**: If changes occur during merge, a new PR is created instead
   of releasing

### Quick Start

#### 1. Create Release Workflow

Create `.github/workflows/release.yml` in your project:

```yaml
name: release

on:
  push: # To create/update release PR and to make release
  pull_request: # To update release PR after manually changed version
    types: [edited]

jobs:
  release-pr:
    uses: powerman/workflows/.github/workflows/release-pr.yml@main
    # Customize inputs if needed (all have sensible defaults):
    # with:
    #   target_branch: 'main'  # Default: repository default branch
    #   pr_branch: 'release-pr'  # Default: 'release-pr'
    #   commit_prefix: 'chore: release'  # Default: 'chore: release'
    #   version_cmd: 'echo "Custom version command here"'  # Optional

  # Optional: Add your own build/upload steps after release
  build-and-upload:
    needs: [release-pr]
    if: ${{ needs.release-pr.outputs.result == 'released' }}
    runs-on: ubuntu-latest
    # ... your build steps

  # Mark release as non-draft and latest.
  finalize:
    needs: [release-pr, build-and-upload]
    if: ${{ needs.release-pr.outputs.result == 'released' }}
    permissions:
      contents: write # To update GitHub release.
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
```

#### 2. Required Repository Settings

In **Settings → Actions → General**:

- ✅ **Allow GitHub Actions to create and approve pull requests**

#### 3. Changelog Configuration

Create `cliff.toml` in your project root. See the [git-cliff
documentation](https://git-cliff.org/docs/configuration) for configuration details.

It is recommended to use <https://github.com/powerman/workflows/blob/main/cliff.toml>
as an example/starting point. There are a couple of places which mention 'chore: release' and
these are important to keep or somehow else handle in your config too.

### Workflow Reference

#### Main Workflow: `release-pr.yml`

The orchestrator workflow that determines what action to take based on the triggering event.

**Inputs:**

- `commit_prefix` (optional): Commit message prefix (default: `'chore: release'`)
- `pr_branch` (optional): Technical branch name (default: `'release-pr'`)
- `target_branch` (optional): Target branch for releases (default: repository default branch)
- `version_cmd` (optional): Shell command to update additional files with the version

**Outputs:**

- `result`: Action taken - `'prepared-pr'`, `'set-version'`, `'released'`, or empty
- `version`: Version that was processed
- `changelog`: Changelog for the version

**Triggers:**

- **Push to target branch**: Creates/updates release PR or performs release
- **PR edited on release branch**: Updates release PR with new version

#### Sub-Workflows

##### `release-pr-prepare.yml`

Creates or updates the release PR when new commits are pushed to the target branch.

**When it runs**: Push to target branch (non-release commits)

**What it does**:

- Calculates next version using git-cliff
- Preserves manually set versions from existing PRs
- Runs custom version command if provided
- Generates changelog and updates CHANGELOG.md
- Creates or updates release PR

##### `release-pr-set-version.yml`

Handles manual version changes in the release PR titles.

**When it runs**: PR title edited on release branch

**What it does**:

- Extracts version from edited PR title
- Runs custom version command with new version
- Regenerates CHANGELOG.md for the new version
- Updates release branch and PR description
- Normalizes PR title format

##### `release-pr-release.yml`

Performs the actual release when the release PR is merged.

**When it runs**: Release PR is merged (detected by commit message patterns)

**What it does**:

- Extracts version from merge commit or PR title
- Checks for race conditions by regenerating CHANGELOG.md
- Creates new release PR if race condition detected
- Creates GitHub release tag and draft release
- Handles both merge commit and squash merge workflows

### Customization Examples

#### Adding Version Command

Update additional files when the version changes:

```yaml
jobs:
  release-pr:
    uses: ./.github/workflows/release-pr.yml
    with:
      version_cmd: |
        # Update the version in package files
        sed -i "s/version = \".*\"/version = \"${RELEASE_PR_VERSION#v}\"/" Cargo.toml
        sed -i "s/__version__ = \".*\"/__version__ = \"${RELEASE_PR_VERSION#v}\"/" src/__init__.py

        # Version available as $RELEASE_PR_VERSION (e.g., "v1.2.3")
        echo "Updated to version: $RELEASE_PR_VERSION"
```

#### Complete Release Workflow with Build

```yaml
name: release

on:
  push:
  pull_request:
    types: [edited]

jobs:
  release-pr:
    uses: ./.github/workflows/release-pr.yml

  build-and-upload:
    needs: [release-pr]
    if: ${{ needs.release-pr.outputs.result == 'released' }}
    permissions:
      contents: write # To upload to GitHub release
      id-token: write # For cosign signing
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build the project
        run: |
          # Your build commands here
          make build
          mkdir -p ./dist
          cp target/release/myapp ./dist/

      - name: Sign assets (optional)
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
```

#### Language-Specific Examples

##### Go Project

```yaml
jobs:
  release-pr:
    uses: ./.github/workflows/release-pr.yml
    with:
      version_cmd: |
        # Update the version in go.mod or version file if needed
        echo "module version: $RELEASE_PR_VERSION"

  build-go:
    needs: [release-pr]
    if: ${{ needs.release-pr.outputs.result == 'released' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
      - run: |
          go build -o ./dist/myapp
          # Upload steps...
```

##### Python Project

```yaml
jobs:
  release-pr:
    uses: ./.github/workflows/release-pr.yml
    with:
      version_cmd: |
        sed -i "s/__version__ = \".*\"/__version__ = \"${RELEASE_PR_VERSION#v}\"/" src/__init__.py

  build-python:
    needs: [release-pr]
    if: ${{ needs.release-pr.outputs.result == 'released' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
      - run: |
          pip install build
          python -m build --outdir ./dist
          # Upload steps...
```

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

### Configuration Details

#### Version Command Environment

When `version_cmd` is executed:

- **Working directory**: Clean state on release branch
- **Timing**: Before CHANGELOG.md generation and commit
- **Environment variable**: `$RELEASE_PR_VERSION` contains full version (e.g., "v1.2.3")
- **State preservation**: Original working directory state is preserved via git stash

#### Supported Project Types

- **Single project per repository** (no monorepo support)
- **Any programming language**
- **Semantic versioning required**
- **Git tags for release versions**
- **CHANGELOG.md managed by git-cliff**
- **Any merge strategy** (merge commit, squash merge, rebase merge)

#### Branch and PR Management

- **Technical branch**: `release-pr` (configurable)
- **Single commit**: Release branch contains only one commit with version and changelog
- **Force push**: Branch is force-pushed on updates to maintain single commit
- **Auto-cleanup**: No manual cleanup required

### Project Requirements

1. **CHANGELOG.md**: Must be in repository root, managed by git-cliff
2. **git-cliff configuration**: Proper `cliff.toml` configuration required
3. **Semantic versioning**: Project must use semver for releases
4. **Git tags**: Releases must be tagged with version numbers
5. **Repository permissions**: Actions must be allowed to create PRs

### Comparison with Alternatives

Release PR fills a unique niche in the automated release ecosystem. Here's how it compares to
other popular solutions:

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

#### 🎯 Strengths & Trade-offs

##### **Release PR** (This project)

**✅ Strengths:**

- **Simplicity**: Easiest to set up and understand
- **Reliability**: Fewer moving parts = fewer bugs
- **Language Agnostic**: Works with any language via `version_cmd`
- **Robust Race Condition Handling**: Prevents incorrect releases
- **Transparent Logic**: Clear, debuggable workflow

**⚠️ Limitations:**

- No built-in monorepo support
- No registry publishing (handled by user workflows)
- Limited `version_cmd` flexibility
- Newer project (less battle-tested)

##### **Google Release Please**

**✅ Strengths:**

- **Feature Rich**: Maximum capabilities
- **Multi-language**: 20+ languages supported out-of-the-box
- **Enterprise Ready**: Used by Google and major projects
- **Monorepo Support**: Excellent workspace handling

**⚠️ Limitations:**

- **Complexity**: Steep learning curve and setup
- **Reliability Issues**: Many [reported
  problems](https://github.com/googleapis/release-please/issues) with large files, performance
- **Over-engineering**: Can be overkill for simple projects
- **Debugging Difficulty**: Complex internal logic

##### **Rust release-pr**

**✅ Strengths:**

- **Perfect Rust Integration**: Native Cargo.toml handling
- **Semver Checking**: Automatic breaking change detection
- **Performance**: Rust binary faster than Node.js alternatives
- **Registry Publishing**: Built-in crates.io support

**⚠️ Limitations:**

- **Rust Only**: Cannot be used for other languages
- **Multi-package Complexity**: Issues with [large
  workspaces](https://github.com/MarcoIeni/release-pr/discussions/1019)
- **Commit Ambiguity**: Struggles with cross-package commits

#### 🏆 When to Choose What

**Choose Release PR when:**

- ✅ You want **simplicity and reliability** over features
- ✅ Working with **any programming language**
- ✅ Need **transparent, debuggable** release process
- ✅ Want **minimal maintenance overhead**
- ✅ Have **single-package repositories**

**Choose Release Please when:**

- ✅ You need **enterprise-grade features**
- ✅ Working with **monorepos** or **multiple languages**
- ✅ Require **built-in registry publishing**
- ✅ Have **complex release requirements**
- ✅ Can invest time in **setup and maintenance**

**Choose release-pr when:**

- ✅ Building **Rust projects exclusively**
- ✅ Need **automatic semver checking**
- ✅ Want **crates.io publishing** built-in
- ✅ Working with **Cargo workspaces**

#### 💡 Release PR's Unique Position

Release PR occupies the **"simple and reliable"** niche:

- **Not the most feature-rich** (that's Release Please)
- **Not the most language-specific** (that's release-pr for Rust)
- **But the most straightforward and dependable** for general use

This makes Release PR ideal for teams who want automated releases without the complexity
overhead of more ambitious tools.
