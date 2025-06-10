# Usage:
#   1. In tests:    echo "multiline data" | debug key "optional title"
#   2. Run bats:    BATS_DEBUG=key,key2 bats …
debug() {
    [[ ! $BATS_DEBUG =~ (^|,)$1(,|$) ]] || batslib_decorate "DEBUG: ${2:-$1}" >&3
}
