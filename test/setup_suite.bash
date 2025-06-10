setup_suite() {
    TEST_REPO=$("${BATS_TEST_DIRNAME}"/test_helper/test_repo)
    export TEST_REPO

    TEST_REPO_DIR="$(git rev-parse --show-toplevel)/.test-repo"
    export TEST_REPO_DIR
}
