<?php

declare(strict_types=1);

$finder = PhpCsFixer\Finder::create()
    ->in([__DIR__ . '/src', __DIR__ . '/scripts', __DIR__ . '/tests'])
    ->append([__DIR__ . '/.php-cs-fixer.dist.php']);

return (new PhpCsFixer\Config())
    ->setRiskyAllowed(true)
    ->setRules([
        '@PSR12' => true,
        'declare_strict_types' => true,
        'ordered_imports' => true,
        'single_line_empty_body' => true,
    ])
    ->setFinder($finder);
