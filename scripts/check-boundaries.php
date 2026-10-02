<?php

declare(strict_types=1);

$root = isset($argv[1]) ? realpath($argv[1]) : dirname(__DIR__);

if ($root === false) {
    fwrite(STDERR, "Boundary check failed: package directory does not exist.\n");
    exit(2);
}

$manifestPath = $root . '/composer.json';
$manifest = is_file($manifestPath) ? json_decode((string) file_get_contents($manifestPath), true) : null;

if (! is_array($manifest)) {
    fwrite(STDERR, "Boundary check failed: composer.json is missing or invalid.\n");
    exit(2);
}

$runtimeRequirements = $manifest['require'] ?? [];
if (! is_array($runtimeRequirements)) {
    fwrite(STDERR, "Boundary check failed: composer.json require must be an object.\n");
    exit(2);
}

$runtimeRequirements = array_filter(
    $runtimeRequirements,
    static fn (mixed $package): bool => $package !== 'php',
    ARRAY_FILTER_USE_KEY,
);

if ($runtimeRequirements !== []) {
    fwrite(STDERR, 'Boundary violation: runtime package dependencies are prohibited: ' . implode(', ', array_keys($runtimeRequirements)) . "\n");
    exit(1);
}

$sourceDirectory = $root . '/src';
$violations = [];

if (is_dir($sourceDirectory)) {
    $files = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($sourceDirectory));

    foreach ($files as $file) {
        if (! $file instanceof SplFileInfo || ! $file->isFile() || $file->getExtension() !== 'php') {
            continue;
        }

        $contents = (string) file_get_contents($file->getPathname());

        foreach (token_get_all($contents) as $token) {
            if (! is_array($token) || ! in_array($token[0], [T_NAME_QUALIFIED, T_NAME_FULLY_QUALIFIED, T_NAME_RELATIVE], true)) {
                continue;
            }

            $name = ltrim($token[1], '\\');
            if ($name === 'CJPH\\Core' || str_starts_with($name, 'CJPH\\Core\\') || str_starts_with($name, 'namespace\\') || ! str_contains($name, '\\')) {
                continue;
            }

            $violations[] = $file->getPathname() . ' references external namespace ' . $name;
            break;
        }

        if (preg_match('/\b(?:BookingId|TenantId|UserId|ServiceDuration|Capacity|BookingPeriod)\b/', $contents, $match) === 1) {
            $violations[] = $file->getPathname() . ' references service-owned business type ' . $match[0];
        }
    }
}

if ($violations !== []) {
    fwrite(STDERR, "Boundary violations:\n - " . implode("\n - ", $violations) . "\n");
    exit(1);
}

fwrite(STDOUT, "Core source and runtime dependency boundaries are clean.\n");
