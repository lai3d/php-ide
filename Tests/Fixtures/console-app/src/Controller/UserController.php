<?php

declare(strict_types=1);

namespace App\Controller;

final class UserController
{
    public function index(): string
    {
        return 'users';
    }

    public function show(int $id): string
    {
        return "user $id";
    }
}
