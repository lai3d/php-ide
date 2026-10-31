<?php

declare(strict_types=1);

namespace Hello;

// Intentionally wrong, for the PHPStan test.
function broken(): int
{
    return undefinedFunction();
}
