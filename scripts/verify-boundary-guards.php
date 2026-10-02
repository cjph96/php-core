<?php

declare(strict_types=1);

$packageRoot = dirname(__DIR__);
$guard = $packageRoot . '/scripts/check-boundaries.php';
$temporaryRoot = sys_get_temp_dir() . '/php-core-boundary-' . bin2hex(random_bytes(6));

mkdir($temporaryRoot, 0777, true);

try {
    $cleanRoot = $temporaryRoot . '/clean';
    mkdir($cleanRoot . '/src', 0777, true);
    copy($packageRoot . '/composer.json', $cleanRoot . '/composer.json');
    file_put_contents($cleanRoot . '/src/Probe.php', "<?php\nnamespace CJPH\\Core;\nfinal class Probe { public function now(): \\DateTimeImmutable { return new \\DateTimeImmutable(); } }\n");
    assertGuardResult($guard, $cleanRoot, 0, 'clean source and manifest');

    $sourceRoot = $temporaryRoot . '/prohibited-source';
    mkdir($sourceRoot . '/src', 0777, true);
    copy($packageRoot . '/composer.json', $sourceRoot . '/composer.json');
    file_put_contents($sourceRoot . '/src/ForbiddenAdapter.php', "<?php\nuse Symfony\\Component\\HttpFoundation\\Request;\n");
    assertGuardResult($guard, $sourceRoot, 1, 'prohibited source dependency');

    $httpRoot = $temporaryRoot . '/prohibited-http-client';
    mkdir($httpRoot . '/src', 0777, true);
    copy($packageRoot . '/composer.json', $httpRoot . '/composer.json');
    file_put_contents($httpRoot . '/src/HttpClient.php', "<?php\nuse Psr\\Http\\Client\\ClientInterface;\n");
    assertGuardResult($guard, $httpRoot, 1, 'prohibited HTTP client contract');

    $dependencyRoot = $temporaryRoot . '/prohibited-package';
    mkdir($dependencyRoot . '/src', 0777, true);
    $manifest = json_decode((string) file_get_contents($packageRoot . '/composer.json'), true, 512, JSON_THROW_ON_ERROR);
    if (! is_array($manifest) || ! is_array($manifest['require'] ?? null)) {
        throw new RuntimeException('Package manifest require section is not an object.');
    }

    $manifest['require']['symfony/http-foundation'] = '^7.0';
    file_put_contents($dependencyRoot . '/composer.json', json_encode($manifest, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));
    assertGuardResult($guard, $dependencyRoot, 1, 'prohibited runtime package');

    $businessRoot = $temporaryRoot . '/prohibited-business-model';
    mkdir($businessRoot . '/src', 0777, true);
    copy($packageRoot . '/composer.json', $businessRoot . '/composer.json');
    file_put_contents($businessRoot . '/src/BookingId.php', "<?php\nfinal class BookingId {}\n");
    assertGuardResult($guard, $businessRoot, 1, 'prohibited business model');
} finally {
    removeTree($temporaryRoot);
}

fwrite(STDOUT, "Boundary probes passed: clean source, prohibited source, prohibited HTTP contract, prohibited business type and prohibited runtime package.\n");

/** @param 0|1 $expectedExit */
function assertGuardResult(string $guard, string $root, int $expectedExit, string $description): void
{
    $command = [PHP_BINARY, $guard, $root];
    $process = proc_open($command, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);

    if (! is_resource($process)) {
        throw new RuntimeException('Unable to run boundary checker for ' . $description);
    }

    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $exitCode = proc_close($process);

    if ($exitCode !== $expectedExit) {
        throw new RuntimeException(sprintf(
            'Boundary probe "%s" expected exit %d, got %d. stdout=%s stderr=%s',
            $description,
            $expectedExit,
            $exitCode,
            trim((string) $stdout),
            trim((string) $stderr),
        ));
    }
}

function removeTree(string $directory): void
{
    if (! is_dir($directory)) {
        return;
    }

    $entries = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($directory, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::CHILD_FIRST,
    );

    foreach ($entries as $entry) {
        if (! $entry instanceof SplFileInfo) {
            continue;
        }

        $entry->isDir() ? rmdir($entry->getPathname()) : unlink($entry->getPathname());
    }

    rmdir($directory);
}
