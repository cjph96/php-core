#!/usr/bin/env bash

set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${OUTPUT_DIR:-}" ]]; then
    output_dir="$OUTPUT_DIR"
    mkdir -p "$output_dir"
else
    output_dir="$(mktemp -d "${TMPDIR:-/tmp}/php-core-consumer.XXXXXX")"
fi

consumer_dir="$output_dir/consumer-$(date +%s)-$$"
mkdir -p "$consumer_dir"

cat > "$consumer_dir/composer.json" <<'JSON'
{
    "name": "php-core/clean-consumer-smoke",
    "type": "project",
    "repositories": [
        {
            "type": "path",
            "url": "__PACKAGE_PATH__",
            "options": {
                "symlink": false,
                "versions": {
                    "cjph96/php-core": "dev-main"
                }
            }
        },
        {
            "packagist.org": false
        }
    ],
    "require": {
        "cjph96/php-core": "dev-main"
    },
    "minimum-stability": "stable",
    "prefer-stable": true
}
JSON

PACKAGE_PATH="$package_root" CONSUMER_MANIFEST="$consumer_dir/composer.json" php -r '
$path = json_decode((string) file_get_contents(getenv("CONSUMER_MANIFEST")), true, 512, JSON_THROW_ON_ERROR);
$path["repositories"][0]["url"] = getenv("PACKAGE_PATH");
file_put_contents(getenv("CONSUMER_MANIFEST"), json_encode($path, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR) . "\n");
'

cd "$consumer_dir"
composer install --no-dev --no-interaction --prefer-dist 2>&1 | tee "$output_dir/composer-install.log"
composer show --installed --format=json > "$output_dir/installed-packages.json"

PACKAGE_ROOT="$package_root" CONSUMER_DIR="$consumer_dir" php -r '
$consumer = getenv("CONSUMER_DIR");
$packages = json_decode((string) file_get_contents($consumer . "/vendor/composer/installed.json"), true, 512, JSON_THROW_ON_ERROR)["packages"];
$names = array_map(static fn (array $package): string => $package["name"], $packages);
if ($names !== ["cjph96/php-core"]) { fwrite(STDERR, "Unexpected installed runtime graph: " . implode(", ", $names) . "\n"); exit(1); }
$mapping = require $consumer . "/vendor/composer/autoload_psr4.php";
$prefix = "CJPH\\Core\\";
if (! isset($mapping[$prefix]) || $mapping[$prefix] !== [$consumer . "/vendor/cjph96/php-core/src"]) {
    fwrite(STDERR, "Generated PSR-4 mapping is missing or incorrect.\n"); exit(1);
}
if (! is_file($consumer . "/vendor/autoload.php")) { fwrite(STDERR, "Generated autoloader is missing.\n"); exit(1); }
$lock = json_decode((string) file_get_contents($consumer . "/composer.lock"), true, 512, JSON_THROW_ON_ERROR);
$lockedNames = array_map(static fn (array $package): string => $package["name"], $lock["packages"]);
if ($lockedNames !== ["cjph96/php-core"]) { fwrite(STDERR, "Unexpected locked runtime graph: " . implode(", ", $lockedNames) . "\n"); exit(1); }
'

cat > "$consumer_dir/behavior.php" <<'PHP'
<?php

declare(strict_types=1);

namespace ConsumerExample;

require __DIR__ . '/vendor/autoload.php';

use CJPH\Core\Time\ElapsedDuration;
use CJPH\Core\Time\InvalidElapsedDuration;

function check(bool $condition, string $message): void
{
    if (! $condition) {
        fwrite(STDERR, $message . "\n");
        exit(1);
    }
}

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

$zero = new ElapsedDuration(0);
$minute = new ElapsedDuration(60);
$max = new ElapsedDuration(PHP_INT_MAX);
$equalMinute = new ElapsedDuration(60);
$positiveMinute = new PositiveDuration(60);
$positiveHour = new PositiveDuration(3600);

check($zero->seconds() === 0, 'The base duration must accept zero.');
check($minute->seconds() === 60, 'The exact seconds value must be retained.');
check($max->seconds() === PHP_INT_MAX, 'PHP_INT_MAX must be retained exactly.');
check($minute->equals($equalMinute), 'Equal independent values must compare equal.');
check($minute->equals($positiveMinute), 'Base-to-subtype equality must compare seconds.');
check($positiveMinute->equals($minute), 'Subtype-to-base equality must compare seconds.');
check(! $minute->equals($positiveHour), 'Unequal subtype seconds must compare unequal.');

try {
    new ElapsedDuration(-1);
    check(false, 'The base duration must reject negative seconds.');
} catch (\InvalidArgumentException $exception) {
    check($exception instanceof InvalidElapsedDuration, 'The package exception must extend InvalidArgumentException.');
}

try {
    new PositiveDuration(0);
    check(false, 'The consumer subtype must reject zero.');
} catch (\InvalidArgumentException) {
}

for ($attempt = 0; $attempt < 10; ++$attempt) {
    check($minute->seconds() === 60, 'Repeated reads must remain stable.');
    check($minute->equals($equalMinute), 'Repeated equality checks must remain stable.');
}

check($zero->seconds() === 0, 'Subtype validation must not change base zero semantics.');
PHP

php "$consumer_dir/behavior.php" 2>&1 | tee "$output_dir/consumer-behavior.log"

cp "$consumer_dir/composer.json" "$output_dir/consumer-composer.json"
cp "$consumer_dir/composer.lock" "$output_dir/consumer-composer.lock"
printf 'Consumer smoke passed. Evidence directory: %s\n' "$output_dir"
