# Check, test and run commands for this host-scripted Loup project.
#
# The program is a script (bin/linkcheck.lpscr) run from source; a script
# entry cannot be compiled (E-BUILD-COMPILED), so there is no build target.
# It runs under Stage0 (`loup-bootstrap run`): on Linux x86-64 the self-hosted
# `loup run` has no `net.tcp`, and Stage0 enforces the capability grants
# the program is given (file system and network only). On macOS, Windows
# and Linux arm64 `loup` and `loup-bootstrap` are both Stage0.

APP            ?= linkcheck
LOUP_BOOTSTRAP ?= loup-bootstrap
RUN            ?= $(LOUP_BOOTSTRAP) run --deny-all --allow-fs --allow-net
SCRIPTS        := $(wildcard bin/*.lpscr) tests/site_server.lpscr
TESTS          ?= $(wildcard tests/*_test.lpscr)
ARGS           ?=
SITE_PORT      ?= 8000
TEST_ARGS      ?=

.PHONY: all run site check test e2e ci clean

all: ci

# Run from source, e.g. `make run ARGS="-v http://127.0.0.1:8000/"`.
# The arguments follow `--` so that Stage0 passes them all to the script.
run:
	$(RUN) bin/$(APP).lpscr -- $(ARGS)

# Serve the test site on 127.0.0.1:$(SITE_PORT) to try linkcheck on, e.g.
# `make site &` then `make run ARGS="http://127.0.0.1:8000/"`. Ctrl-C (or
# kill) stops it.
site:
	$(RUN) tests/site_server.lpscr -- $(SITE_PORT) tests/fixtures/site

# Type-check each entry script (and the tests' fixture server) and every
# lib/ module it imports.
check:
	@for script in $(SCRIPTS); do \
		echo "check $$script"; \
		$(LOUP_BOOTSTRAP) check --no-color $$script || exit 1; \
	done

# Unit tests (tests/*_test.lpscr), one file at a time and one test at a
# time (--no-parallel): in parallel, the 1.26.0 runner fails random tests
# with an empty RuntimeError on a busy machine. The runner grants no
# network: the crawler is tested on sites held in memory
# (tests/fakesite.lpscr).
# Narrow the run: `make test TESTS=tests/crawler_test.lpscr TEST_ARGS="--filter depth"`.
test:
	@status=0; for t in $(TESTS); do \
		$(LOUP_BOOTSTRAP) test --no-color --no-parallel --file $$t $(TEST_ARGS) || status=1; \
	done; exit $$status

# End-to-end tests: the command-line errors, then linkcheck against
# tests/fixtures/site served by tests/site_server.lpscr (net.http.serve) on
# a free port of 127.0.0.1, always stopped at the end.
e2e:
	bash tests/e2e.sh $(LOUP_BOOTSTRAP)

# Everything CI runs, ending with a smoke test of the entry script.
ci: check test e2e
	$(RUN) bin/$(APP).lpscr -- --version

clean:
	rm -rf .temp .loup-cache
