#!/usr/bin/env bats
# Smoke tests for Release PR workflows using act (local execution)
# Minimizes GitHub API usage while testing workflow logic

#shellcheck disable=SC2155,SC2164

setup_file() {
    "${BATS_TEST_DIRNAME}"/test_helper/setup_repo

    cd "$TEST_REPO_DIR"

    cat >go.mod <<'EOF'
module test-project

go 1.24
EOF
    cat >main.go <<'EOF'
package main

import "fmt"

func main() {
    fmt.Println("Hello, World!")
}
EOF
    git add .
    git commit -m "feat: add initial version"

    cp ../cliff.toml .
    git add .
    git commit -m "chore: setup git-cliff"
}

setup() {
    load 'test_helper/bats-support-0.3.0/load' # This is required by bats-assert!
    load 'test_helper/bats-assert-2.1.0/load'
    load 'test_helper/debug/load'

    export DEFAULT_BRANCH=main
    export COMMIT_PREFIX='chore: release'
    export PR_BRANCH=release-pr
    export TARGET_BRANCH="$DEFAULT_BRANCH"

    cd "$TEST_REPO_DIR"
    git reset --hard >/dev/null
    git checkout "$DEFAULT_BRANCH" &>/dev/null
}

event_json() {
    local event_json="$(mktemp "$BATS_TEST_TMPDIR/event.XXXXXXXXXX.json")"
    "$BATS_TEST_DIRNAME/test_helper/generate_event" "$@" >"$event_json"
    debug event "$*" <"$event_json"
    echo "$event_json"
}

@test "feature branch push: should be skipped (no action)" {
    git checkout -b feature/a
    git commit --allow-empty -m 'feat: add a'
    git push -u origin --force feature/a

    run act push \
        --workflows .github/workflows/release.yml \
        --eventpath "$(event_json push)"
    assert_success
    assert_output --partial "Skip push: target branch is not ${TARGET_BRANCH}"
    refute_output --partial '::set-output:: action='
    refute_output --regexp '::notice::(Created new|Updated existing) release PR'
    refute_output --partial 'Job failed' # We run many workflows, some may output "Job succeeded".
    debug act "release.yml" <<<"$output"

    # Verify no release PR was created
    run gh pr list --repo "$TEST_REPO" --state open --head "$PR_BRANCH" --json number
    assert_success
    assert_output "[]"
}

@test "target branch push: should prepare release PR" {
    git checkout "$TARGET_BRANCH"
    git commit --allow-empty -m 'feat: add b'
    git push

    run act push \
        --workflows .github/workflows/release.yml \
        --eventpath "$(event_json push)"
    assert_success
    assert_output --partial '::set-output:: action=prepare'
    assert_output --regexp '::notice::(Created new|Updated existing) release PR'
    refute_output --partial 'Job failed' # We run many workflows, some may output 'Job succeeded'.
    debug act "release.yml" <<<"$output"

    # Wait a moment for GitHub API to sync with repo.
    sleep 2

    # Verify release PR was created.
    run gh pr list --repo "$TEST_REPO" --state open --head "$PR_BRANCH" --json title --jq '.[0].title'
    assert_success
    assert_output --regexp '^chore: release v[0-9]+\.[0-9]+\.[0-9]+$'
}

@test "release PR edit: should update version" {
    # Get existing PR for version editing.
    local pr_info=$(gh pr list --repo "$TEST_REPO" --state open --head release-pr --json number,title)
    local pr_count=$(echo "$pr_info" | jq length)

    if [ "$pr_count" -eq 0 ]; then
        skip "No release PR available - run previous test first"
    fi

    local pr_number=$(echo "$pr_info" | jq -r '.[0].number')

    # Edit PR title to set custom version in loose format.
    local new_title="chore: release  1.1.0 "
    gh pr edit "$pr_number" --repo "$TEST_REPO" --title "$new_title"

    run act pull_request \
        --workflows .github/workflows/release.yml \
        --eventpath "$(event_json pull_request --branch "$TARGET_BRANCH" \
            --action edited --pr-number "$pr_number" --pr-title "$new_title")"
    assert_success
    assert_output --partial '::set-output:: action=set-version'
    assert_output --partial '::set-output:: result=set-version'
    assert_output --partial '::set-output:: version=v1.1.0'
    refute_output --partial 'Job failed' # We run many workflows, some may output 'Job succeeded'.
    debug act "release.yml" <<<"$output"

    # Wait for update to process
    sleep 2

    # Verify PR title was preserved/updated
    run gh pr view "$pr_number" --repo "$TEST_REPO" --json title --jq '.title'
    assert_success
    assert_output 'chore: release v1.1.0'
}

@test "release merge: should create release" {
    # Get the current release PR
    local pr_info=$(gh pr list --repo "$TEST_REPO" --state open --head release-pr --json number,title)
    local pr_count=$(echo "$pr_info" | jq length)

    if [ "$pr_count" -eq 0 ]; then
        skip "No release PR available - run previous tests first"
    fi

    local pr_number=$(echo "$pr_info" | jq -r '.[0].number')
    local pr_title=$(echo "$pr_info" | jq -r '.[0].title')
    echo "# Merging PR #$pr_number: $pr_title" >&3

    # Merge the PR to trigger release
    run gh pr merge "$pr_number" --repo "$TEST_REPO" --squash --delete-branch
    assert_success

    # Wait for merge to complete
    sleep 2

    # Run release workflow locally with act
    git pull
    run act push \
        --workflows .github/workflows/release.yml \
        --eventpath "$(event_json push)"
    assert_success
    assert_output --partial '::set-output:: action=release'
    assert_output --partial "release"
    refute_output --partial 'Job failed' # We run many workflows, some may output 'Job succeeded'.
    debug act "release.yml" <<<"$output"

    # Wait for release creation
    sleep 2

    # Verify release was created
    run gh release list --repo "$TEST_REPO" --limit 1 --json tagName,name,isDraft
    assert_success
    refute_output "[]"

    local tag_name=$(echo "$output" | jq -r '.[0].tagName')
    local release_name=$(echo "$output" | jq -r '.[0].name')
    local is_draft=$(echo "$output" | jq -r '.[0].isDraft')
    echo "# Created release: $release_name (tag: $tag_name, draft: $is_draft)" >&3

    assert_equal "$tag_name" "v1.1.0"
    assert_equal "$is_draft" "true"

    # Verify tag was created
    run git pull
    run git tag -l "$tag_name"
    assert_output "$tag_name"
}
