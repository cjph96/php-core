<?php

declare(strict_types=1);

use CJPH\Core\Time\ElapsedDuration;
use CJPH\Core\Time\InvalidElapsedDuration;

$consumerDirectory = $argv[1] ?? null;
$expectedIdentityPath = $argv[2] ?? null;
if (! is_string($consumerDirectory) || ! is_string($expectedIdentityPath)) {
    fwrite(STDERR, "Usage: verify-consumer.php <consumer-directory> <expected-identity.json>\n");
    exit(2);
}

$expectedIdentityContents = file_get_contents($expectedIdentityPath);
if (! is_string($expectedIdentityContents)) {
    throw new RuntimeException('Expected distribution identity could not be read.');
}

$expectedIdentity = json_decode($expectedIdentityContents, true, 512, JSON_THROW_ON_ERROR);
if (! is_array($expectedIdentity)) {
    throw new RuntimeException('Expected distribution identity must be a JSON object.');
}

$expectedVersion = $expectedIdentity['version'] ?? null;
$expectedDist = $expectedIdentity['dist'] ?? null;
if (! is_string($expectedVersion) || ! is_array($expectedDist)) {
    throw new RuntimeException('Expected distribution identity is incomplete.');
}

$expectedUrl = $expectedDist['url'] ?? null;
$expectedSha256 = $expectedIdentity['sha256'] ?? null;
if (! is_string($expectedUrl) || ! is_string($expectedSha256) || parse_url($expectedUrl, PHP_URL_SCHEME) !== 'file') {
    throw new RuntimeException('Expected distribution checksum identity is incomplete.');
}

$archivePath = parse_url($expectedUrl, PHP_URL_PATH);
if (! is_string($archivePath) || ! is_file($archivePath)) {
    throw new RuntimeException('Expected local distribution archive is missing.');
}

$actualSha256 = hash_file('sha256', $archivePath);
$actualSha1 = hash_file('sha1', $archivePath);
if ($actualSha256 !== $expectedSha256 || $actualSha1 !== ($expectedDist['shasum'] ?? null)) {
    throw new RuntimeException('Expected local distribution archive checksum changed.');
}

$installedJson = $consumerDirectory . '/vendor/composer/installed.json';
$installedContents = file_get_contents($installedJson);
if (! is_string($installedContents)) {
    throw new RuntimeException('Consumer Composer installation metadata is missing.');
}

$installed = json_decode($installedContents, true, 512, JSON_THROW_ON_ERROR);
if (! is_array($installed) || ! isset($installed['packages']) || ! is_array($installed['packages'])) {
    throw new RuntimeException('Consumer Composer installation metadata has an unexpected shape.');
}

$installedPackageNames = [];
$installedPackage = null;
foreach ($installed['packages'] as $candidate) {
    if (! is_array($candidate)) {
        throw new RuntimeException('Consumer Composer package metadata has an unexpected shape.');
    }

    $candidateName = $candidate['name'] ?? null;
    if (! is_string($candidateName)) {
        throw new RuntimeException('Consumer Composer package metadata is missing a package name.');
    }

    $installedPackageNames[] = $candidateName;
    if ($candidateName === 'cjph96/php-core') {
        $installedPackage = $candidate;
    }
}

sort($installedPackageNames);
if ($installedPackageNames !== ['cjph96/php-core']) {
    throw new RuntimeException('Consumer runtime graph contains an unexpected package set.');
}

if (! is_array($installedPackage) || ($installedPackage['version'] ?? null) !== $expectedVersion) {
    throw new RuntimeException(sprintf('Expected installed cjph96/php-core %s.', $expectedVersion));
}

$lockContents = file_get_contents($consumerDirectory . '/composer.lock');
if (! is_string($lockContents)) {
    throw new RuntimeException('Consumer lockfile is missing.');
}

$lock = json_decode($lockContents, true, 512, JSON_THROW_ON_ERROR);
if (! is_array($lock) || ! isset($lock['packages']) || ! is_array($lock['packages'])) {
    throw new RuntimeException('Consumer lockfile has an unexpected shape.');
}

$developmentPackages = $lock['packages-dev'] ?? [];
if (! is_array($developmentPackages) || $developmentPackages !== []) {
    throw new RuntimeException('Consumer lockfile unexpectedly contains development packages.');
}

$lockedPackages = [];
foreach ($lock['packages'] as $candidate) {
    if (! is_array($candidate)) {
        throw new RuntimeException('Consumer lockfile package metadata has an unexpected shape.');
    }

    $candidateName = $candidate['name'] ?? null;
    if (! is_string($candidateName)) {
        throw new RuntimeException('Consumer lockfile package metadata is missing a package name.');
    }

    $lockedPackages[$candidateName] = $candidate;
}

if (! isset($lockedPackages['cjph96/php-core']) || count($lockedPackages) !== 1) {
    throw new RuntimeException('Consumer lockfile contains an unexpected runtime package set.');
}

$lockedPackage = $lockedPackages['cjph96/php-core'];
$lockedVersion = $lockedPackage['version'] ?? null;
if ($lockedVersion !== $expectedVersion) {
    throw new RuntimeException(sprintf('Expected lockfile package cjph96/php-core %s.', $expectedVersion));
}

$lockedDist = $lockedPackage['dist'] ?? null;
if (! is_array($lockedDist)) {
    throw new RuntimeException('Consumer lockfile is missing the installed distribution identity.');
}

foreach (['url', 'type', 'reference', 'shasum'] as $identityField) {
    $expectedValue = $expectedDist[$identityField] ?? null;
    $actualValue = $lockedDist[$identityField] ?? null;
    if (! is_string($expectedValue) || $actualValue !== $expectedValue) {
        throw new RuntimeException(sprintf('Consumer lockfile distribution %s differs from its immutable fixture identity.', $identityField));
    }
}

require $consumerDirectory . '/vendor/autoload.php';

$duration = new ElapsedDuration(3671);
if ($duration->seconds() !== 3671 || ! $duration->equals(new ElapsedDuration(3671))) {
    throw new RuntimeException('Installed consumer autoloader did not expose the approved duration contract.');
}

try {
    new ElapsedDuration(-1);
    throw new RuntimeException('Negative elapsed duration was accepted.');
} catch (InvalidElapsedDuration) {
    // Expected public validation behavior.
}

if (! (new ReflectionClass(ElapsedDuration::class))->isReadOnly()) {
    throw new RuntimeException('ElapsedDuration is expected to remain immutable.');
}

printf("consumer=%s package=%s elapsed_duration=passed\n", $consumerDirectory, $expectedVersion);
