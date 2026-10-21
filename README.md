# loup-cmd-linkcheck

A link checker for web sites written as a [Loup](https://code-craft.ai/references/loup)
script: give it a start URL and it reads every page of that site it can
reach, checks every link and image on them with a few workers at a time,
and reports the broken ones with the pages that refer to them, as text and
as an HTML page. It exits with status 1 when anything is broken, so it can
guard a site's build.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.scripted` project: a thin `.lpscr` entry script in
`bin/` over `.lpscr` and `host.dual` modules in `lib/`, run from source by
Stage0 with the network capability granted.

## Requirements

- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later (`loup-bootstrap` on `PATH`); see [Installing Loup Lite](#installing-loup-lite).
- `make`, `bash`, `curl` and `python3` for the tests (python3 finds a free
  port, curl waits for the test server). Nothing is built.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
./bin/linkcheck.lpscr http://127.0.0.1:8000/                          # the shebang grants fs and net
loup-bootstrap run --allow-net bin/linkcheck.lpscr -- -v http://127.0.0.1:8000/
make site &                                                           # serve the test site on port 8000
make run ARGS="--html report.html http://127.0.0.1:8000/"
make ci                                                               # check, unit tests, end-to-end tests
```

**Which runner.** linkcheck runs under Stage0, `loup-bootstrap run`. On
Linux x86-64 `loup run` is the self-hosted driver, which has no `net.tcp`
in 1.26.0 and does not parse `await group`, `?.` or `in`; on macOS,
Windows and Linux arm64 `loup` is Stage0 too. The shebang line,
`#!/usr/bin/env -S loup-bootstrap run --deny-all --allow-fs --allow-net`,
grants the network and the file system (for `--html`) and nothing else.
Stage0 takes long options before `--` as its own, so with the shebang write
them after `--`: `./bin/linkcheck.lpscr -- --max-depth 2 URL` (short ones,
`-d 2`, work directly).

The test site (`make site`, the server in `tests/site_server.lpscr` on
`net.http.serve`) has a few broken links on purpose:

```text
$ ./bin/linkcheck.lpscr http://127.0.0.1:8000/; echo "status $?"
linkcheck http://127.0.0.1:8000/
Read 7 pages, checked 17 links: 6 broken, 3 skipped (2 external, 1 not http), 3 ignored.

404 Not Found  http://127.0.0.1:8000/docs/deep/two.html
    linked from http://127.0.0.1:8000/docs/deep/one.html

404 Not Found  http://127.0.0.1:8000/docs/diagram.svg
    linked from http://127.0.0.1:8000/docs/

500 Internal Server Error  http://127.0.0.1:8000/error
    linked from http://127.0.0.1:8000/
    linked from http://127.0.0.1:8000/index.html

404 Not Found  http://127.0.0.1:8000/img/missing.png
    linked from http://127.0.0.1:8000/
    linked from http://127.0.0.1:8000/index.html

error: too many redirects  http://127.0.0.1:8000/loop
    linked from http://127.0.0.1:8000/
    linked from http://127.0.0.1:8000/index.html

404 Not Found  http://127.0.0.1:8000/missing.html
    linked from http://127.0.0.1:8000/
    linked from http://127.0.0.1:8000/about.html
    linked from http://127.0.0.1:8000/about.html?from=home&lang=en
    linked from http://127.0.0.1:8000/index.html

Links to other sites were not checked (--external checks them).
status 1
```

Only the start page's links (`-d 0`), each reported on standard error as it
is checked (`-v`):

```text
$ ./bin/linkcheck.lpscr -v -d 0 http://127.0.0.1:8000/ 2>&1 | head -12
200 OK: http://127.0.0.1:8000/
200 OK: http://127.0.0.1:8000/style.css
200 OK: http://127.0.0.1:8000/app.js
200 OK: http://127.0.0.1:8000/logo.svg
404 Not Found: http://127.0.0.1:8000/img/missing.png
200 OK: http://127.0.0.1:8000/about.html
200 OK: http://127.0.0.1:8000/about.html?from=home&lang=en
200 OK: http://127.0.0.1:8000/docs/
404 Not Found: http://127.0.0.1:8000/missing.html
200 OK: http://127.0.0.1:8000/redirect (redirected to http://127.0.0.1:8000/about.html)
error: too many redirects: http://127.0.0.1:8000/loop (redirected to http://127.0.0.1:8000/loop)
500 Internal Server Error: http://127.0.0.1:8000/error
```

Just the broken links, leaving a part of the site out (`-x`), and a part
with nothing broken:

```text
$ ./bin/linkcheck.lpscr -q -x http://127.0.0.1:8000/docs/ http://127.0.0.1:8000/
500 Internal Server Error  http://127.0.0.1:8000/error
    linked from http://127.0.0.1:8000/
404 Not Found  http://127.0.0.1:8000/img/missing.png
    linked from http://127.0.0.1:8000/
error: too many redirects  http://127.0.0.1:8000/loop
    linked from http://127.0.0.1:8000/
404 Not Found  http://127.0.0.1:8000/missing.html
    linked from http://127.0.0.1:8000/
    linked from http://127.0.0.1:8000/about.html
    linked from http://127.0.0.1:8000/about.html?from=home&lang=en
$ ./bin/linkcheck.lpscr http://127.0.0.1:8000/clean/; echo "status $?"
linkcheck http://127.0.0.1:8000/clean/
Read 3 pages, checked 4 links: 0 broken.
No broken links.
status 0
```

`--html report.html` writes the same as a page: the counts, a table of the
broken links with the pages that link to them, and a table of every
checked link with its status, all values escaped
([tests/expected/report.html](tests/expected/report.html) is the test
site's, with `@URL@` for the address).

### Options

| Option | Meaning |
|---|---|
| `-d`, `--max-depth N` | read pages at most N links away from the start page (default: no limit); links on the last pages are still checked |
| `-c`, `--concurrency N` | run up to N checks at a time (1 to 64, default 4) |
| `-e`, `--external` | also check links to other sites, with `HEAD` (`GET` if `HEAD` is refused); they are never read |
| `-x`, `--exclude PREFIX` | skip links that start with PREFIX; may be repeated |
| `-o`, `--html FILE` | also write the report as an HTML page |
| `-q`, `--quiet` | print only the broken links |
| `-v`, `--verbose` | print each link on standard error as it is checked |
| `-h`, `--help` / `-V`, `--version` | help text / `linkcheck (loup-cmd-linkcheck) 0.1.0` |

Long options take `--name=value` or `--name value` and may be shortened to
any unambiguous prefix (`--max=2`); `--` ends the options.

What counts:

- **Pages** are the URLs with the start URL's scheme, host and port whose
  reply is `text/html`: they are read for links (`href` of `a`, `area`,
  `link`; `src` of `img`, `script`, `iframe`, `source` and the other media
  elements), with `<base href>` honoured and comments, `script` and `style`
  text skipped.
- **Links** are resolved, stripped of their `#fragment`, and checked once
  each, however many pages link to them. Redirects are followed (at most 5).
- **Broken** means a final status of 400 or more, no answer at all
  (`error: Connection refused`), a malformed URL or a redirect loop.
- **Skipped** links are counted, not checked: other sites (without
  `--external`), `https://` and other schemes, and `--exclude` prefixes.
  `mailto:`, `tel:`, `javascript:`, `data:` and fragment-only links are
  **ignored**.

### Exit status

`0` when no link is broken, `1` when some are (the start page included),
`2` for a usage error, a start URL that is not `http://`, a missing network
grant or an HTML report that cannot be written.

## What this example shows

- **`net.http`, from the other side.** `net.http` is a server; the client
  is `lib/fetch.lpscr` over `net.tcp.connect`, speaking HTTP/1.1 with
  `net.http`'s own types: the request is a `Request` with `Headers` and
  `HttpVersion.HTTP_1_1`, and the reply's status an `HttpStatus`
  (`isRedirect()`, the reason phrase). `lib/httpwire.loup` reads replies as
  bytes, with `Content-Length` and chunked bodies. The tests serve their
  site with `net.http.serve`.
- **`async`/`await` and `await group`.** The crawler works level by level:
  for each level an `await group` spawns the workers, which take URLs from
  a shared queue, and ends when they have all found it empty, so the next
  level starts with exact depths. The crawl itself is a **top-level
  `await`** in `bin/linkcheck.lpscr`.
- **`atomic { }`** around every check-then-act on shared state: taking a
  job from the queue, adding a URL to the set of known URLs (only the first
  sighting queues it) and recording an outcome together with the broken
  set. Loup 1.26.0 runs the tasks one after another, but nothing relies on
  that.
- **Sets** (`set[string]` of known URLs, broken URLs, pages read, ignored
  links) and **`in`** (`url in this.known`, `tag in HREF_ELEMENTS`,
  `"&" in text`).
- **A generator**, `gen func links_in(html): Iterable[Link]`, which yields
  each link as the tokenizer reaches it.
- **`?.`**: `checked.reply?.is_html() ?? false` asks a reply that may not
  exist whether it is a page.
- **Template fences**: the HTML report is `(html)` fences with `{% for %}`,
  `{% if %}`/`{% else %}` and the `escape` filter on every value.
- **An interface for testing**: the crawler takes a `Fetcher` (an async
  method), so the unit tests crawl sites held in memory
  (`tests/fakesite.lpscr`) and count the requests it makes.
- `net.addressing` (`Url.parse`, `resolve`, origins) and an enum with
  payloads (`LinkTarget.Web(url)`, `Unsupported`, `Malformed`, `Ignored`).

## Limitations (Loup 1.26.0)

- **No TLS**: `https://` links are counted as skipped and an `https://`
  start URL is refused.
- **No timeouts**: `net.tcp` has none, so a server that accepts a
  connection and never answers stops the crawl.
- **One request at a time.** Loup 1.26.0 runs async tasks eagerly, one
  after another, so `--concurrency` does not yet make the crawl faster;
  the crawler is written for tasks that interleave.
- Only HTML is read for links: URLs in CSS (`url(...)`), `srcset` and
  scripts are not followed, and fragments are not checked against the
  page's anchors. Each request uses a new connection, and at most 8 MiB of
  a reply is read.

## Layout

```text
bin/linkcheck.lpscr          # the program (host.scripted entry script)
lib/appinfo.loup             # name, version, exit statuses, limits
lib/args.loup                # option parsing (getopt_long style)
lib/usage.loup               # --help and --version text
lib/urls.loup                # normalizing, origins, what a link points at
lib/httpwire.loup            # requests and replies on the wire
lib/links.lpscr              # the link-extracting generator
lib/fetch.lpscr              # the Fetcher interface and the HTTP client
lib/crawler.lpscr            # the crawl: levels, workers, outcomes
lib/report.lpscr             # the text report and the HTML page
tests/*_test.lpscr           # unit tests, no sockets (make test)
tests/fakesite.lpscr         # a site in memory for the unit tests
tests/site_server.lpscr      # the test site's server (net.http.serve)
tests/e2e.sh                 # linkcheck against the test site (make e2e)
tests/expected/              # expected reports
tests/fixtures/site/         # the test site
specs/linkcheck/             # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every check and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
