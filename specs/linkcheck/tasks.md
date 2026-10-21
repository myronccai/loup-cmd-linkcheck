# Tasks: linkcheck

- [x] 1. Layout: `bin/linkcheck.lpscr` over `lib/` modules, Stage0 runner with `--deny-all --allow-fs --allow-net`, grant check
  - _Requirements: 5.3_
- [x] 2. Option parser from a table: clusters, `--name=value`, unambiguous prefixes, repeated `--exclude`, counts, usage errors (status 2)
  - _Requirements: 5.1, 5.2, 5.4_
- [x] 3. URLs: one spelling, origins, link classification, the start URL's checks
  - _Requirements: 1.3, 1.5, 2.4_
- [x] 4. HTTP over net.tcp with net.http's types: requests, status lines, headers, chunked bodies, Content-Length, bodiless replies
  - _Requirements: 1.1, 2.2_
- [x] 5. Link extraction as a generator: elements and attributes, character references, `<base>`, comments, script and style text
  - _Requirements: 1.2_
- [x] 6. Crawler: levels with `await group`, workers on a shared queue, `atomic { }` around every check-then-act, depth limit, skipped and ignored links
  - _Requirements: 1.1, 1.3, 1.4, 1.5, 3.1, 3.2_
- [x] 7. Checks: redirects (at most 5), HEAD for other sites with the GET fallback, outcomes
  - _Requirements: 2.1, 2.2, 2.3_
- [x] 8. Reports: text (full and `--quiet`), `--verbose` progress, HTML with template fences and `| escape`; exit statuses
  - _Requirements: 4.1, 4.2, 4.3, 4.4_
- [x] 9. Unit tests with a site in memory; end-to-end tests against a net.http.serve fixture site on 127.0.0.1
  - _Requirements: all_
