<?php

declare(strict_types=1);

namespace CJPH\Core\Tests\Time;

use CJPH\Core\Tests\Time\Fixture\PositiveDuration;
use CJPH\Core\Time\ElapsedDuration;
use CJPH\Core\Time\InvalidElapsedDuration;
use PHPUnit\Framework\TestCase;

final class ElapsedDurationTest extends TestCase
{
    public function testItPreservesSupportedBoundaryIntegers(): void
    {
        foreach ([0, 60, PHP_INT_MAX] as $seconds) {
            self::assertSame($seconds, (new ElapsedDuration($seconds))->seconds());
        }
    }

    public function testNegativeSecondsThrowTheDocumentedException(): void
    {
        $this->expectException(InvalidElapsedDuration::class);

        new ElapsedDuration(-1);
    }

    public function testPackageExceptionCanBeCaughtAsNativeInvalidArgumentException(): void
    {
        try {
            new ElapsedDuration(-1);
            self::fail('A negative duration must be rejected.');
        } catch (\InvalidArgumentException $exception) {
            self::assertInstanceOf(InvalidElapsedDuration::class, $exception);
        }
    }

    public function testEqualityUsesSecondsRatherThanObjectIdentity(): void
    {
        $first = new ElapsedDuration(60);
        $sameValue = new ElapsedDuration(60);
        $differentValue = new ElapsedDuration(61);

        self::assertNotSame($first, $sameValue);
        self::assertTrue($first->equals($sameValue));
        self::assertFalse($first->equals($differentValue));
    }

    public function testRepeatedReadsAndComparisonsPreserveBothValues(): void
    {
        $first = new ElapsedDuration(60);
        $second = new ElapsedDuration(60);

        for ($attempt = 0; $attempt < 10; ++$attempt) {
            self::assertSame(60, $first->seconds());
            self::assertTrue($first->equals($second));
        }

        self::assertSame(60, $first->seconds());
        self::assertSame(60, $second->seconds());
    }

    public function testReadonlyConsumerSubtypePreservesInheritedDurationContract(): void
    {
        $baseZero = new ElapsedDuration(0);
        $base = new ElapsedDuration(60);
        $subtype = new PositiveDuration(60);
        $differentSubtype = new PositiveDuration(61);

        self::assertSame(0, $baseZero->seconds());
        self::assertSame(60, $subtype->seconds());
        self::assertTrue($base->equals($subtype));
        self::assertTrue($subtype->equals($base));
        self::assertFalse($base->equals($differentSubtype));
        self::assertFalse($differentSubtype->equals($base));

        try {
            new PositiveDuration(0);
            self::fail('The consumer subtype must reject zero.');
        } catch (\InvalidArgumentException) {
            self::assertSame(0, $baseZero->seconds());
        }
    }
}

namespace CJPH\Core\Tests\Time\Fixture;

use CJPH\Core\Time\ElapsedDuration;

final readonly class PositiveDuration extends ElapsedDuration
{
    public function __construct(int $seconds)
    {
        if ($seconds <= 0) {
            throw new \InvalidArgumentException('Positive duration is required.');
        }

        parent::__construct($seconds);
    }
}
