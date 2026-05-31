# redis-guard.bash — shared Redis test helper for xfleet subcommand BATS suites.
#
# Single source of truth for the Redis-availability skip guard and the default
# Redis URL, so the SC-3 default cannot drift per-file. Source from a BATS file:
#
#   load "../lib/redis-guard.bash"
#
# Then in setup(): export XFLEET_REDIS_URL="${XFLEET_REDIS_URL:-${XFLEET_TEST_REDIS_URL}}"
# and guard Redis-dependent tests with: if ! redis_available; then skip "redis unavailable"; fi

# SC-3 locked default — must match tools/xfleet/lib/redis.sh.
XFLEET_TEST_REDIS_URL="${XFLEET_REDIS_URL:-redis://127.0.0.1:6379}"

# redis_available — returns 0 if Redis answers PING at XFLEET_TEST_REDIS_URL.
redis_available() {
    redis-cli -u "${XFLEET_TEST_REDIS_URL}" ping >/dev/null 2>&1
}

# unique_name — a per-test stream/inbox name derived from the BATS test name and
# the PID, sanitized to [a-zA-Z0-9_], so concurrent/repeated tests never collide.
unique_name() {
    local sanitized
    sanitized="$(printf '%s' "${BATS_TEST_NAME}" | tr -cs 'a-zA-Z0-9_' '_')"
    printf 'test_%s_%s' "${sanitized}" "$$"
}
