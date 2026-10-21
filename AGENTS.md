# AGENTS.md

This repository is `linkcheck`, a link checker for web sites written in the
Loup programming language, part of the loup-cmd series of example
applications. Given a start URL it reads every page of that site it can
reach, checks every link and image on them, and reports the broken ones
with the pages that refer to them, as text and as an HTML page. It is a
`host.scripted` project: the `.lpscr` script in `bin/`, run from source by
`loup-bootstrap run` with the `fs` and `net` capabilities, imports `.lpscr`
and `host.dual` modules from `lib/`. Nothing is compiled.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership, execution
modes and projects, errors and diagnostics, the standard library, and common
mistakes. Load those only as needed.

## Code layout

```text
.
├── package.lppkg                # manifest: name, version, toolchain, [build] entry (bin/linkcheck.lpscr), [test] pattern
├── Makefile                     # run, site, check, test, e2e, ci, clean
├── bin/
│   └── linkcheck.lpscr          # entry script (host.scripted, executable): options, checks, top-level await of the crawl, reports
├── lib/
│   ├── appinfo.loup             # APP_NAME, APP_VERSION, USER_AGENT, exit statuses, limits
│   ├── args.loup                # OPTION_SPECS, struct Options, parse_args(), find_long(), find_short(), parse_count()
│   ├── usage.loup               # usage(), version_line()
│   ├── urls.loup                # enum LinkTarget, normalize(), origin_key(), origin_of(), classify(), resolve_text(), start_url_problem()
│   ├── httpwire.loup            # class HttpReply, make_request(), request_text(), parse_reply() and its parts, dechunk()
│   ├── links.lpscr              # struct Link, gen func links_in(), decode_entities()
│   ├── fetch.lpscr              # interface Fetcher, class HttpFetcher (net.tcp), io_reason()
│   ├── crawler.lpscr            # CrawlSettings, Outcome, BrokenLink, Summary, class Crawler
│   └── report.lpscr             # text_report(), summary_line(), html_report() (template fences)
├── tests/
│   ├── *_test.lpscr             # unit tests: func test_*() and async func test_*() (no sockets)
│   ├── fakesite.lpscr           # FakeSite: a Fetcher that serves a site from memory
│   ├── site_server.lpscr        # net.http.serve over tests/fixtures/site, plus /redirect, /loop, /error
│   ├── e2e.sh                   # end-to-end: linkcheck against site_server on 127.0.0.1
│   ├── expected/                # expected reports (@URL@ is the server's address)
│   └── fixtures/site/           # the test site
├── specs/linkcheck/             # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
└── .github/workflows/ci.yml     # installs Loup and runs `make ci`
```

## Check, run and test

Prerequisites: Loup 1.26.0 (`loup-bootstrap` on `PATH`), `make`, `bash`,
`curl` and `python3` (the end-to-end tests use them to find a free port
and to wait for the test server).

Loup Lite comes from <https://github.com/code-craft-ai-company/loup-releases>;
[README.md](README.md#installing-loup-lite) has the install commands.

| Task | Command | Notes |
|------|---------|-------|
| Run | `make run ARGS="-v http://127.0.0.1:8000/"` | `loup-bootstrap run --deny-all --allow-fs --allow-net bin/linkcheck.lpscr -- ARGS` |
| Serve the test site | `make site` (`SITE_PORT=8000`) | `tests/site_server.lpscr`; stop it with Ctrl-C |
| Run directly | `./bin/linkcheck.lpscr URL` | the shebang grants the capabilities; long options only after `--` |
| Type-check | `make check` | `loup-bootstrap check FILE` for `bin/linkcheck.lpscr` and `tests/site_server.lpscr` |
| Unit tests | `make test` | each `tests/*_test.lpscr` in turn, `--no-parallel` |
| One test file | `make test TESTS=tests/crawler_test.lpscr` | |
| Matching tests | `make test TEST_ARGS="--filter depth"` | |
| End-to-end tests | `make e2e` | `tests/e2e.sh`: starts the test site on a free port, always stops it |
| Everything CI runs | `make ci` | check, test, e2e, then `--version` |
| Clean | `make clean` | removes `.temp/`, `.loup-cache/` |

Run `make ci` before reporting a change as done. The tests never leave
127.0.0.1: never add a test with `--external` or a real host name.

Toolchain facts this project depends on (Loup 1.26.0, Linux x86-64):

- `net.tcp` and `net.http.serve` work only under Stage0 (`loup-bootstrap
  run`) with `--allow-net`; `net.http` has no client. The test runner
  grants no network, hence `tests/fakesite.lpscr`.
- `await group`, `?.`, `in`, sets, generators and interpolation filters
  (`| escape`) are Stage0-only; the self-hosted `loup run` rejects them.
- Async tasks run eagerly, one after another; `await group` waits for all
  of its spawns. `atomic { }` may hold no `await`.
- Mutating a collection held in a field (`this.known.add(url)`,
  `this.outcomes[url] = o`) is allowed in a plain method; assigning a field
  needs a `modifier` method, which can only be called inside `safe { }`,
  and `await` is not allowed there. So the crawler keeps its state in
  collections and its async methods are not `modifier`.
- The test runner awaits `async func test_*(): Task[void]`.
- A template fence holds at most one `{% for %}` (a second one, even after
  the first, redeclares its hidden iterator: `E_REDECLARED`), so each table
  is rendered by its own fence. Inside a function the fence's lines carry
  the function's indentation, which is removed.
- A struct cannot have a class-typed field (`E_STRUCT_CLASS_FIELD`):
  `Outcome`, `BrokenLink` and `Checked` are classes.
- `unreachable`, `attempt`, `from` and `template` are reserved words.

## Making a change

1. Update the spec in `specs/linkcheck/` (see [specs/README.md](specs/README.md)).
2. Change the code: parsing, URLs and the wire format in the `host.dual`
   modules, the crawl and the reports in the `.lpscr` modules, start-up in
   `bin/linkcheck.lpscr`.
3. Add or update unit tests in `tests/` (crawler behaviour against a
   `FakeSite`) and cases in `tests/e2e.sh`; when a report changes on
   purpose, update `tests/expected/`.
4. Run `make ci`.
5. Tick the finished tasks in `specs/linkcheck/tasks.md`.

## Conventions

- `bin/linkcheck.lpscr` is `@mode(host.scripted)` with the shebang
  `#!/usr/bin/env -S loup-bootstrap run --deny-all --allow-fs --allow-net`
  and the executable bit. Grant no more capabilities than it uses.
- `lib/*.loup` are `@mode(host.dual)` and use nothing Stage0-only;
  `lib/*.lpscr` are `@mode(host.scripted)` and hold the async code, the
  generator, the sets and the template fences.
- Imports are relative: `from ..lib.crawler import (...)` in `bin/` and
  `tests/`, `from .urls import (...)` inside `lib/`.
- Reports sort by URL, so that they do not depend on the order of the work.
- Every value in the HTML report goes through `| escape`.
- Keep `APP_VERSION` and `USER_AGENT` in `lib/appinfo.loup` and `version` in
  `package.lppkg` in step.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
