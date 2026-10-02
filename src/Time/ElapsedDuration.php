<?php

declare(strict_types=1);

namespace CJPH\Core\Time;

readonly class ElapsedDuration
{
    public function __construct(private int $seconds)
    {
        if ($seconds < 0) {
            throw new InvalidElapsedDuration('Elapsed duration cannot be negative.');
        }
    }

    final public function seconds(): int
    {
        return $this->seconds;
    }

    final public function equals(self $other): bool
    {
        return $this->seconds === $other->seconds;
    }
}
