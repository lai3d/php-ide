# PHPIDE Roadmap

Status: ✅ done · 🚧 in progress · ⬜ planned

Estimates are Claude Code session time.

Forked from GoIDE (same path RustIDE and CSharpIDE took), so the editor shell (tabs, gutter, folding,
search/replace, Git, terminal, LSP + DAP clients, multi-window, session restore) already exists.
The work is porting the language-specific layer to PHP.

Toolchain on the dev Mac: `php` + `composer` from Homebrew, `intelephense` from npm (global).

## Phase 0 — Fork

| # | Item | Notes | Est. |
|---|---|---|---|
| 0.1 | ✅ Fork GoIDE → PHPIDE | Rename targets, bundle ID `io.github.lai3d.phpide`, Composer + PHPUnit example in `Examples/hello` | 0.1h |

## Phase 1 — Port to the PHP toolchain

| # | Item | Notes | Est. |
|---|---|---|---|
| 1.1 | ✅ Language server | Intelephense (`--stdio`, default) or Phpactor (`language-server`) with fallback; Settings picker + licence key; Composer/npm global bins on the search path; `indexingStarted`/`indexingEnded` → status; Workspace tests ported to PHP | 0.6h |
| 1.1b | ⬜ Premium-feature tests | Intelephense (free) has no rename / code actions / implementation / folding / semantic tokens / inlay hints: re-add PHP versions of those tests against Phpactor (phar) and port the remaining gopls-gated Core tests | 0.5h |
| 1.2 | ✅ PHP highlighter | Hand-written lexer (`PHPHighlighter`): `<?php`/`?>` + inline HTML, heredoc/nowdoc, `$variables`, interpolation, attributes `#[...]`, PHPDoc tags, casts, `match`/`enum`/`readonly` | 0.5h |
| 1.3 | ✅ Run script | Run configurations point at a PHP script (root `*.php`, `public/index.php`, `bin/*`, `artisan`); ⌘R runs `php <script> <args>`; toolbar/menu wording de-Go'd ("PHP" menu, "No script") | 0.3h |
| 1.3a | ✅ Clickable PHP output | `file.php:12`, `file.php(12)` and `… in /x/file.php on line 12` links in Output / Tests | 0.1h |
| 1.3b | ✅ Syntax check (⌘B) | `php -l` over every project PHP file; parse errors land in Problems (merged with LSP diagnostics) | 0.2h |
| 1.3c | ✅ Static analysis | PHPStan (`vendor/bin/phpstan analyse --error-format=json`) or Psalm (`--output-format=json`) if installed → Problems | 0.3h |
| 1.3d | ✅ Composer commands | PHP menu: composer install / update / dump-autoload / validate replace the go vet / generate / mod items | 0.1h |
| 1.4 | ✅ PHPUnit runner | `vendor/bin/phpunit --teamcity` (or Pest) streamed into the Tests panel: classes → methods → data sets, pass / fail / skip, failure messages, durations | 0.4h |
| 1.4a | ✅ Test discovery & gutter | Find `test*` methods / `#[Test]` / `@test` in `*Test.php`; gutter ▶ / ✓ / ✗; run test at cursor (`--filter`), run file, run all | 0.3h |
| 1.4b | ✅ Jump to test / failure | Click a test → its method; failure `file.php:12` → line; toolbar/menu wording (Test File, no "package") | 0.1h |
| 1.5 | ✅ Xdebug setup | Detect Xdebug (`php -m`); "Install Xdebug" runs `pecl install xdebug` in Output; clear message when missing | 0.2h |
| 1.5a | 🚧 DAP adapter | Download vscode-php-debug (VSIX from GitHub releases) into Application Support on first use; run it with `node` over stdio | 0.3h |
| 1.5b | 🚧 Debug a script (⌥⌘R) | `launch` with program / cwd / args / env; breakpoints (incl. conditions), call stack, variables, step over / into / out, continue | 0.5h |
| 1.5c | 🚧 Debug test at cursor | PHPUnit under Xdebug with `--filter` for the method at the caret | 0.2h |
| 1.5d | 🚧 Listen for Xdebug | "Start Listening" (port 9003) to debug web requests / CLI runs started elsewhere | 0.2h |
| 1.6 | ⬜ Run configurations | Script + args + env, built-in web server (`php -S localhost:8000 -t public`), Composer scripts from `composer.json` | 0.5h |
| 1.7 | ⬜ Snippets & settings | PHP snippets (`fn`, `class`, `foreach`, `pubf`, `ctor`, …); php / node / intelephense / licence-key path overrides | 0.4h |
| 1.8 | ⬜ CI & release | PHP + Intelephense in GitHub Actions, tagged `PHPIDE-vX.Y.Z.zip`, app icon, IDE Toolbox catalog entry | 0.5h |

## Phase 2 — PHP-specific features

| # | Item | Notes | Est. |
|---|---|---|---|
| 2.1 | ⬜ Composer panel | Packages from `composer.json`/`composer.lock`; require / update / remove, `composer outdated`, run scripts | 0.6h |
| 2.2 | ⬜ Formatting | PHP-CS-Fixer / Laravel Pint / phpcbf on save when present in `vendor/bin` | 0.3h |
| 2.3 | ⬜ Mixed HTML/PHP templates | Highlight HTML/JS/CSS outside `<?php ?>`; Blade / Twig basic highlighting | 0.6h |
| 2.4 | ⬜ Framework support | Laravel `artisan` / Symfony `bin/console` command runner; route list | 0.6h |
| 2.5 | ⬜ Coverage | PHPUnit `--coverage-clover` with Xdebug/PCOV → gutter tints and per-file % | 0.5h |
| 2.6 | ⬜ Database hook | Open `.env` DB settings in DBIDE | 0.2h |

**User must do manually** (duration outside Claude's control): Intelephense premium licence key (optional,
for rename / code actions), Apple Developer Program enrollment + notarization if a signed build is wanted.
