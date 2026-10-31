Fixture for PHPIDE's end-to-end tests. `tests/MoreTest.php` and `src/Broken.php` fail on purpose.

    composer install
    PHPIDE_PHPUNIT_PROJECT=$PWD PHPIDE_PHPSTAN_PROJECT=$PWD swift test   # from the repo root, with absolute paths
