<?php

declare(strict_types=1);

require __DIR__ . '/src/Greeter.php';

use Hello\Greeter;

$greeter = new Greeter();
echo $greeter->greet($argv[1] ?? 'PHPIDE'), PHP_EOL;
