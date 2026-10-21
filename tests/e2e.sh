#!/usr/bin/env bash
# End-to-end tests for linkcheck: the command-line errors first, then
# crawls of tests/fixtures/site, which tests/site_server.lpscr serves with
# net.http.serve on a free port of 127.0.0.1. Expected reports are in
# tests/expected/ with @URL@ standing for the server's address. Nothing
# leaves 127.0.0.1: --external is never used, and the fixture's links to
# other sites are only counted. An EXIT trap stops the server.
#
# usage: tests/e2e.sh [LOUP_BOOTSTRAP]     (run from the repository root)

set -u
LOUP=${1:-loup-bootstrap}
GRANTS=(run --deny-all --allow-fs --allow-net)
SCRIPT=bin/linkcheck.lpscr
TMP=$(mktemp -d)
SERVER_PID=""
pass=0
fail=0

stop_server() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2> /dev/null
        wait "$SERVER_PID" 2> /dev/null
        SERVER_PID=""
    fi
}
trap 'stop_server; rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM

free_port() {
    python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# linkcheck ARGS...: run the script once, stdin empty.
linkcheck() {
    timeout 60 "$LOUP" "${GRANTS[@]}" "$SCRIPT" -- "$@" < /dev/null
}

# same NAME EXPECTED ACTUAL
same() {
    if [ "$2" == "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1"
        diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/    /' | head -20
    fi
}

# run NAME STATUS ARGS...: run linkcheck, check its status; its output is
# left in $TMP/out and $TMP/err.
run() {
    local name=$1 want_status=$2
    shift 2
    linkcheck "$@" > "$TMP/out" 2> "$TMP/err"
    same "$name: status" "$want_status" "$?"
}

# expected FILE: an expected report with the server's URL filled in.
expected() {
    sed "s#@URL@#$URL#g" "tests/expected/$1"
}

# --- command line ---------------------------------------------------------------

HINT="Try 'linkcheck --help' for more information."
run "version" 0 --version
same "version: stdout" "linkcheck (loup-cmd-linkcheck) 0.1.0" "$(cat "$TMP/out")"
run "help" 0 --help
same "help: first line" "usage: linkcheck [OPTION]... URL" "$(head -1 "$TMP/out")"
run "no URL" 2
same "no URL: stderr" "linkcheck: missing URL
$HINT" "$(cat "$TMP/err")"
run "two URLs" 2 http://127.0.0.1:1/ http://127.0.0.1:2/
same "two URLs: stderr" "linkcheck: extra operand 'http://127.0.0.1:2/'
$HINT" "$(cat "$TMP/err")"
run "bad option" 2 -Z http://127.0.0.1:1/
same "bad option: stderr" "linkcheck: invalid option -- 'Z'
$HINT" "$(cat "$TMP/err")"
run "ambiguous" 2 --ex http://127.0.0.1:1/
same "ambiguous: stderr" "linkcheck: option '--ex' is ambiguous; possibilities: '--external' '--exclude'
$HINT" "$(cat "$TMP/err")"
run "bad depth" 2 --max-depth=deep http://127.0.0.1:1/
same "bad depth: stderr" "linkcheck: invalid depth: 'deep'
$HINT" "$(cat "$TMP/err")"
run "no workers" 2 -c 0 http://127.0.0.1:1/
same "no workers: stderr" "linkcheck: invalid concurrency: '0' (1 to 64)
$HINT" "$(cat "$TMP/err")"
run "https" 2 https://127.0.0.1:1/
same "https: stderr" "linkcheck: https is not supported (Loup 1.26.0 has no TLS): 'https://127.0.0.1:1/'
$HINT" "$(cat "$TMP/err")"
run "relative URL" 2 index.html
same "relative URL: stderr" "linkcheck: not an absolute URL: 'index.html'
$HINT" "$(cat "$TMP/err")"

timeout 60 "$LOUP" run --deny-all --allow-fs "$SCRIPT" -- http://127.0.0.1:1/ < /dev/null > "$TMP/out" 2> "$TMP/err"
same "no net grant: status" 2 $?
same "no net grant: stderr" "linkcheck: network access is not granted: run linkcheck with \`loup-bootstrap run --allow-net\`" "$(cat "$TMP/err")"

# A start URL where nothing listens is one broken link.
CLOSED=$(free_port)
run "nothing there" 1 "http://127.0.0.1:$CLOSED/"
same "nothing there: stdout" "linkcheck http://127.0.0.1:$CLOSED/
Read 0 pages, checked 1 link: 1 broken.

error: Connection refused  http://127.0.0.1:$CLOSED/" "$(cat "$TMP/out")"

# --- the fixture site -------------------------------------------------------------

PORT=$(free_port)
URL="http://127.0.0.1:$PORT"
timeout 300 "$LOUP" "${GRANTS[@]}" tests/site_server.lpscr -- "$PORT" tests/fixtures/site > "$TMP/server.log" 2>&1 &
SERVER_PID=$!
ready=no
for _ in $(seq 1 100); do
    if curl -s -o /dev/null "$URL/clean/"; then
        ready=yes
        break
    fi
    kill -0 "$SERVER_PID" 2> /dev/null || break
    sleep 0.1
done
same "server started" yes "$ready"
if [ "$ready" != yes ]; then
    cat "$TMP/server.log"
    echo "e2e: $pass passed, $((fail + 1)) failed (the fixture server did not start)"
    exit 1
fi

# The whole site.
run "site" 1 "$URL/"
same "site: report" "$(expected site.txt)" "$(cat "$TMP/out")"
same "site: stderr" "" "$(cat "$TMP/err")"

# The same with one worker and with many: the same report.
run "one worker" 1 -c 1 "$URL/"
same "one worker: report" "$(expected site.txt)" "$(cat "$TMP/out")"
run "many workers" 1 --concurrency=64 "$URL/"
same "many workers: report" "$(expected site.txt)" "$(cat "$TMP/out")"

# Only the broken links; each checked link on stderr with -v.
run "quiet" 1 -qv "$URL/"
same "quiet: report" "$(expected site.txt | sed -n '/^[0-9e]/,$p' | grep -v '^$' | grep -v '^Links to other sites')" "$(cat "$TMP/out")"
same "verbose: lines" "$(expected verbose.txt | sort)" "$(sort "$TMP/err")"

# Depth limits: 0 reads the start page only, 1 also the pages it links to.
run "depth 0" 1 -d 0 "$URL/"
same "depth 0: summary" "Read 1 page, checked 12 links: 4 broken, 2 skipped (1 external, 1 not http), 3 ignored." "$(sed -n 2p "$TMP/out")"
run "depth 1" 1 --max-depth 1 "$URL/"
same "depth 1: summary" "Read 4 pages, checked 15 links: 5 broken, 3 skipped (2 external, 1 not http), 3 ignored." "$(sed -n 2p "$TMP/out")"

# Excluded prefixes are not checked.
run "exclude" 1 -x "$URL/docs" --exclude="$URL/loop" "$URL/"
same "exclude: summary" "Read 3 pages, checked 10 links: 3 broken, 6 skipped (3 excluded, 2 external, 1 not http), 3 ignored." "$(sed -n 2p "$TMP/out")"

# A corner of the site with nothing broken: status 0.
run "clean" 0 "$URL/clean/"
same "clean: report" "linkcheck $URL/clean/
Read 3 pages, checked 4 links: 0 broken.
No broken links." "$(cat "$TMP/out")"

# The HTML report.
run "html" 1 -q --html "$TMP/report.html" "$URL/"
same "html: page" "$(expected report.html)" "$(cat "$TMP/report.html")"
run "html, cannot write" 2 -q -o "$TMP/no/such/dir/report.html" "$URL/clean/"
same "html, cannot write: stderr" "linkcheck: cannot write $TMP/no/such/dir/report.html: No such file or directory" "$(cat "$TMP/err")"

kill -0 "$SERVER_PID" 2> /dev/null
same "server still running" 0 $?
stop_server

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
