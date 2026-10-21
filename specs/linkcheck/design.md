# Design: linkcheck

## Overview

`bin/linkcheck.lpscr` is a `host.scripted` script that Stage0 runs with the
`fs` and `net` capabilities. Its top-level statements parse `args()` into
`Options` (usage errors exit 2), answer `--help` and `--version`, check
that the URL is an absolute `http://` URL and that `net` is granted, build
a `Crawler` over an `HttpFetcher`, `await crawler.crawl()` at the top
level, and print the text report from `crawler.summary()` (and write the
HTML one). The status is 1 when the summary holds a broken link.

```text
crawl ─► level 0 ─► await group { spawn work() × N } ─► level 1 ─► ... ─► summary()
              work(): atomic take ─► visit(job) ─► check(url): fetch, redirects
                                         └► links_in(page) ─► found() ─► note(): atomic known/queue
```

## Modules

| Module | Contents |
|---|---|
| `bin/linkcheck.lpscr` | top level: options, URL and grant checks, the crawl (top-level `await`), reports, status |
| `lib/appinfo.loup` | name, version, user agent, exit statuses, default and maximum concurrency, redirect and size limits |
| `lib/args.loup` | `OptionSpec` table, `find_long` (unambiguous prefixes), `find_short`, `parse_count`, `Options`, `parse_args` |
| `lib/usage.loup` | `usage()`, `version_line()` |
| `lib/urls.loup` | `LinkTarget` enum (`Ignored`, `Malformed`, `Unsupported`, `Web`), `normalize`, `origin_key`, `origin_of`, `scheme_of`, `classify`, `resolve_text`, `start_url_problem` |
| `lib/httpwire.loup` | `HttpReply`; `make_request` (a `net.http.Request`), `request_text`; `header_end`, `parse_status_line`, `parse_headers`, `dechunk`, `parse_reply` |
| `lib/links.lpscr` | `Link`, `gen func links_in`, `decode_entities`, `is_link_attribute` |
| `lib/fetch.lpscr` | `interface Fetcher { async func fetch(method, url) }`, `HttpFetcher` over `net.tcp`, `io_reason` |
| `lib/crawler.lpscr` | `CrawlSettings`, `Outcome`, `BrokenLink`, `Summary`, `Crawler` |
| `lib/report.lpscr` | `summary_line`, `skipped_phrase`, `broken_lines`, `text_report`, `html_report` |

### URLs

Every URL is kept in one spelling (`normalize`): lower-case scheme and
host, no default port, no fragment, `/` for an empty path, dot segments
removed. Two URLs are on the same site when their `origin_key`s
(`scheme://host:port`, port always written) are equal. `classify(base,
reference)` turns a link into a `LinkTarget`: empty, fragment-only and
`mailto:`/`tel:`/`javascript:`/`data:` references are `Ignored`, ones
that `Url.resolve` rejects or that have no host are `Malformed`, non-http
URLs `Unsupported`, the rest `Web`.

### HTTP

`HttpFetcher.fetch` connects with `net.tcp.connect`, writes the request
(`GET` or `HEAD`, `Host`, `User-Agent`, `Accept`, `Connection: close`),
reads until the server closes (at most 8 MiB, into an `io.streams`
`ByteWriter`) and calls `parse_reply`. A failed connection is an `Err`
with the system's reason (`Connection refused`). `parse_reply` works on
bytes: it finds the blank line, parses the status line into an
`HttpStatus` (keeping the server's phrase for a code `net.http` does not
know) and the header fields into a `CaseInsensitiveDictionary`
(`header_fields`), then takes the body: none for `HEAD`, 1xx, 204 and 304;
de-chunked for `Transfer-Encoding: chunked`; cut to `Content-Length`
otherwise. Field names are case-insensitive, and servers do send
`content-type` or `LOCATION`: the dictionary finds a field in any case and
keeps the server's spelling. It holds one value per name, so repeated
lines are joined with `, ` (RFC 9110, 5.3): `Transfer-Encoding: gzip` and
`transfer-encoding: chunked` read as `gzip, chunked`, and a
`Content-Length` sent twice (`42, 42`) counts when both agree
(`declared_length`; RFC 9112, 6.3), while two different lengths, like a
length that is not a number, are ignored and the body runs to the end of
the connection.

### Crawling

`Crawler` holds its shared state in collections (`known`, `queue`,
`next_queue`, `outcomes`, `broken`, `pages`, `referrers`, `skipped`,
`ignored`), so its async methods need not be `modifier` methods (those
would have to be called inside `safe { }`, where `await` is not allowed).

- `crawl()`: puts the start URL in `known` and `queue`; then per level an
  `await group` spawns `workers` tasks of `work()` and ends when all have
  returned; the next level is `next_queue`.
- `work()`: repeatedly takes the first job in an `atomic { }` block and
  visits it, until the queue is empty.
- `visit(job)`: checks the URL (`GET` on the site, `HEAD` elsewhere) and
  records the outcome. A page is read when it is on the site, not broken,
  `text/html` (`checked.reply?.is_html() ?? false`), not deeper than
  `max_depth`, still on the site after redirects and not read before (an
  atomic test-and-add on `pages`). `links_in` yields its links; a `base`
  link changes the base for the ones after it; the others go to `found()`.
- `found()`/`note()`: classify the link; in one atomic block add the page
  to the URL's referrers and, if the URL was not known, add it to `known`.
  The first sighting decides: a malformed URL is recorded as broken, an
  excluded, unsupported or (without `--external`) external URL is counted
  as skipped, anything else goes to `next_queue` one level deeper.
- `check(url, method)`: follows up to 5 redirects to `http` targets (a
  redirect to anything else is the answer itself), retries a `HEAD`
  refused with 405 or 501 as `GET`, and returns the `Outcome` (final
  status and reason, or status 0 with the error) and the reply.
- `record()`: stores the outcome and updates `broken` in one atomic block;
  with `--verbose` it prints `LABEL: URL` on standard error.
- `summary()`: outcomes sorted by URL, broken links with their sorted
  referrers, skipped counts by reason, ignored count.

### Reports

The text report is the start URL, the summary line (`Read N pages, checked
M links: B broken, S skipped (reasons), I ignored.`), each broken link
(`LABEL  URL` and `    linked from PAGE` lines) and a hint when external
links were skipped; `--quiet` keeps only the broken links. The HTML report
renders the two tables and the referrer lists with separate `(html)`
fences, one `{% for %}` each (a fence cannot hold two), and puts them in
the page's fence with `{% if %}`/`{% else %}`; every value goes through
`| escape`.

## Error handling

- Usage errors, a bad start URL, a missing grant: `linkcheck: MESSAGE` and
  `Try 'linkcheck --help' for more information.` (no hint for the grant),
  status 2.
- An unwritable `--html` file: `linkcheck: cannot write FILE: REASON`,
  status 2.
- Everything about a link is an outcome, never an error of the program.

## Testing

- Unit tests (no sockets: the Stage0 test runner grants no `net`): options
  and their errors, URLs and classification, the wire format (requests,
  status lines, headers, chunked bodies, bodiless and malformed replies),
  the link extractor (elements, quoting, references, comments, script and
  style text, the fixture's index page), the crawler against
  `tests/fakesite.lpscr` (counts, depth, redirects, `--external` with HEAD
  and the GET fallback, `<base>`, exclusions, a broken start, one worker
  against sixteen), and both reports.
- `tests/e2e.sh`: command-line errors and the missing grant; a start URL
  where nothing listens; then the fixture site from
  `tests/site_server.lpscr` on a free port of 127.0.0.1: the full report
  (and the same with 1 and 64 workers), `--quiet` and `--verbose`, depths
  0 and 1, exclusions, a clean part (status 0), the HTML report compared
  with `tests/expected/report.html`, and an unwritable report file.
  `--external` is never used.

## Differences from other link checkers

linkcheck is not a copy of one program; it does what `linkchecker`,
`muffet` and `lychee` share at their core, within Loup 1.26.0: no TLS
(`https://` is skipped), no timeouts, no robots.txt, no CSS or `srcset`
URLs, no anchor checks, one connection per request, and tasks that do not
yet run at the same time.
