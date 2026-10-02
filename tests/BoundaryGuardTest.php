<?php

declare(strict_types=1);

namespace CJPH\Core\Tests;

use PHPUnit\Framework\TestCase;

final class BoundaryGuardTest extends TestCase
{
    public function testDisposableFixturesExerciseTheSameBoundaryGuard(): void
    {
        $process = proc_open(
            [PHP_BINARY, dirname(__DIR__) . '/scripts/verify-boundary-guards.php'],
            [1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
            $pipes,
        );

        self::assertIsResource($process);
        $stdout = stream_get_contents($pipes[1]);
        $stderr = stream_get_contents($pipes[2]);
        fclose($pipes[1]);
        fclose($pipes[2]);

        self::assertSame(0, proc_close($process), trim((string) $stderr));
        self::assertStringContainsString('Boundary probes passed', (string) $stdout);
    }
}
