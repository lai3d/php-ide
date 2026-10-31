<?php

declare(strict_types=1);

namespace Hello\Tests;

use Hello\Greeter;
use PHPUnit\Framework\TestCase;

final class GreeterTest extends TestCase
{
    public function testGreet(): void
    {
        $this->assertSame('Hello, World!', (new Greeter())->greet('World'));
    }
}
