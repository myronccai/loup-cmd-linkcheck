# Requirements: linkcheck

## Introduction

`linkcheck` checks the links of a web site. Given a start URL, it reads
every page of that site (same scheme, host and port) that can be reached
from it, checks every link and image the pages contain, and reports the
broken ones together with the pages that refer to them, as text and
optionally as an HTML page. It exits with status 1 when anything is
broken, so that it can guard a site's build in CI.

It is a `host.scripted` project of the loup-cmd series, run by Stage0
(`loup-bootstrap run --allow-net`): the standard library's `net.tcp`,
which its HTTP client is built on, works only there, and so do several of
the language features it is there to show: `await group`, top-level
`await`, `atomic { }` blocks, sets, generators, `?.`, `in`, and template
fences with `{% for %}` and the `escape` filter. Its HTTP side uses
`net.http`'s `Headers`, `HttpStatus` and `Request`; the tests serve a
fixture site with `net.http.serve` on 127.0.0.1.

## Requirements

### Requirement 1: Crawling a site

**User Story:** As a site author, I want every page of my site read and
every link on it checked so that no visitor meets a dead link.

#### Acceptance Criteria

1. WHEN linkcheck is given an `http://` URL, THE crawler SHALL fetch it
   with `GET`, and read each page whose response is `text/html` and whose
   URL has the start URL's origin (scheme, host, port).
2. THE link extractor SHALL find `href` and `src` attributes of `a`,
   `area`, `link`, `img`, `script`, `iframe`, `frame`, `source`, `embed`,
   `audio`, `video` and `track` elements, decode HTML character references
   in them, honour `<base href>`, and ignore comments and the text of
   `script` and `style` elements.
3. THE crawler SHALL resolve each link against its page, drop the
   fragment, and check every distinct URL once, however many pages link to
   it, remembering every page that does.
4. WHEN `--max-depth N` is given, THE crawler SHALL read pages at most N
   links away from the start page; links found on the last pages are still
   checked. Without it there is no limit.
5. THE crawler SHALL ignore `mailto:`, `tel:`, `javascript:` and `data:`
   links, and links that start with an `--exclude` prefix.

### Requirement 2: Checking a link

**User Story:** As a site author, I want to know why each link is broken.

#### Acceptance Criteria

1. THE checker SHALL follow up to 5 redirects (`301`, `302`, `303`, `307`,
   `308` with a `Location`), and report a link as broken with `too many
   redirects` after that.
2. THE checker SHALL report a link as broken WHEN its final status is 400
   or more (`404 Not Found`), or WHEN no answer came (`error: Connection
   refused`, a name that does not resolve, a malformed reply).
3. WHEN `--external` is given, THE checker SHALL check links to other
   sites with `HEAD` (and `GET` when `HEAD` gives 405 or 501) and never
   read them for links. Without it they are counted as skipped.
4. THE checker SHALL count `https://` and other non-HTTP links as skipped
   (Loup 1.26.0 has no TLS), and refuse an `https://` start URL.

### Requirement 3: Concurrency

**User Story:** As a user with a large site, I want several checks to run
at a time.

#### Acceptance Criteria

1. THE crawler SHALL work level by level, with `--concurrency N` workers
   (default 4, 1 to 64) taking the level's URLs from a shared queue; the
   next level starts when every worker is done.
2. THE crawler SHALL make each check-then-act on shared state (taking a
   URL from the queue, adding a URL to the set of known URLs, updating the
   counters and the results) an `atomic { }` block with no suspension
   point inside.

### Requirement 4: Reports and exit status

**User Story:** As a site author, I want a report I can read in a terminal
and one I can publish.

#### Acceptance Criteria

1. THE text report SHALL give the start URL and the counts (pages read,
   links checked, broken, skipped), then each broken link, sorted by URL,
   with its status and the pages that link to it, sorted.
2. WHEN `--quiet` is given, THE text report SHALL hold the broken links
   only; WHEN `--verbose` is given, THE program SHALL print each link's
   status on standard error as it is checked.
3. WHEN `--html FILE` is given, THE program SHALL also write an HTML page
   with the same summary, the broken links with their pages, and every
   checked link with its status, all text escaped.
4. THE program SHALL exit with status 0 when nothing is broken, 1 when a
   link is broken, and 2 for a usage error or a start URL it cannot use.

### Requirement 5: Command line

**User Story:** As a user, I want GNU-style options and clear errors.

#### Acceptance Criteria

1. THE parser SHALL accept `-d N` / `--max-depth N` / `--max-depth=N`,
   `-c N` / `--concurrency N`, `-e` / `--external`, `-x PREFIX` /
   `--exclude PREFIX` (repeatable), `-o FILE` / `--html FILE`, `-q` /
   `--quiet`, `-v` / `--verbose`, `-h` / `--help` and `-V` / `--version`,
   with clustered short flags and `--` to end the options.
2. WHEN an option is unknown, lacks its value or has a bad number, or the
   URL is missing, extra, not absolute, or not `http`, THE program SHALL
   print `linkcheck: MESSAGE` and `Try 'linkcheck --help' for more
   information.` on standard error and exit with status 2.
3. WHEN the `net` capability is not granted, THE program SHALL say so and
   exit with status 2.
4. `--version` SHALL print `linkcheck (loup-cmd-linkcheck) 0.1.0`.
