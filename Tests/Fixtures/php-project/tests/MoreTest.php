<?php
declare(strict_types=1);
namespace Hello\Tests;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
final class MoreTest extends TestCase
{
    #[Test]
    public function fails(): void { echo "printed\n"; $this->assertSame(1, 2, 'numbers differ'); }
    public function testSkipped(): void { $this->markTestSkipped('later'); }
    #[DataProvider('cases')]
    public function testAdd(int $a, int $b): void { $this->assertSame($a, $b); }
    public static function cases(): array { return ['same' => [1, 1], 'diff' => [1, 2]]; }
}
