#!/usr/bin/env bash

set -Eeuo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${OUTPUT_DIR:-}" ]]; then
    printf 'OUTPUT_DIR must point to a disposable evidence directory outside the package.\n' >&2
    exit 2
fi

fail() {
    printf 'distribution-smoke: %s\n' "$1" >&2
    exit 1
}

case "$OUTPUT_DIR/" in
    "$PACKAGE_ROOT/"*) fail 'OUTPUT_DIR must be outside the package checkout' ;;
esac

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
case "$OUTPUT_DIR/" in
    "$PACKAGE_ROOT/"*) fail 'OUTPUT_DIR must resolve outside the package checkout' ;;
esac
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/php-core-distribution.XXXXXX")"
ARTIFACT_DIR="$OUTPUT_DIR/artifacts"
PACKAGE_INDEX="$OUTPUT_DIR/package-index.json"
mkdir -p "$ARTIFACT_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

write_consumer_manifest() {
    local target="$1"
    local package_constraint="$2"
    local php_constraint="${3:-~8.5.0}"

    mkdir -p "$target"
    php -r '
        $indexContents = file_get_contents($argv[1]);
        if (! is_string($indexContents)) {
            throw new RuntimeException("Fixture package index could not be read.");
        }
        $index = json_decode($indexContents, true, 512, JSON_THROW_ON_ERROR);
        $packages = $index["packages"]["cjph96/php-core"] ?? null;
        if (! is_array($packages)) {
            throw new RuntimeException("Fixture package index has an unexpected shape.");
        }
        $manifest = [
            "name" => "fixture/consumer",
            "type" => "project",
            "require" => ["php" => $argv[2], "cjph96/php-core" => $argv[3]],
            "repositories" => [
                ["type" => "package", "package" => $packages],
                ["packagist.org" => false],
            ],
            "minimum-stability" => "stable",
            "prefer-stable" => true,
            "config" => ["allow-plugins" => new stdClass()],
        ];
        echo json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR), "\n";
    ' "$PACKAGE_INDEX" "$php_constraint" "$package_constraint" >"$target/composer.json"
}

composer_run() {
    local project_dir="$1"
    local log_file="$2"
    shift 2

    local composer_home="$WORK_DIR/composer-home-$(basename "$project_dir")"
    local cache_dir="$WORK_DIR/composer-cache-$(basename "$project_dir")"
    if ! (cd "$project_dir" && env -u COMPOSER_AUTH -u COMPOSER_TOKEN COMPOSER_HOME="$composer_home" COMPOSER_CACHE_DIR="$cache_dir" composer "$@") >"$log_file" 2>&1; then
        return 1
    fi
}

copy_package_payload() {
    local target="$1"
    local version="$2"
    mkdir -p "$target/src"
    cp "$PACKAGE_ROOT/README.md" "$target/README.md"
    cp "$PACKAGE_ROOT/CHANGELOG.md" "$target/CHANGELOG.md"
    cp "$PACKAGE_ROOT/LICENSE" "$target/LICENSE"
    cp -R "$PACKAGE_ROOT/src/." "$target/src/"
    php -r '
        $manifest = json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
        if (isset($manifest["version"])) {
            fwrite(STDERR, "production composer.json must not hardcode a package version\n");
            exit(1);
        }
        unset($manifest["require-dev"], $manifest["autoload-dev"], $manifest["scripts"], $manifest["config"]);
        $manifest["version"] = $argv[2];
        echo json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR), "\n";
    ' "$PACKAGE_ROOT/composer.json" "$version" >"$target/composer.json"
}

check_payload() {
    local archive="$1"
    local version="$2"
    local listing="$3"

    tar -tzf "$archive" | sed 's#^\./##' | sed '/^$/d' >"$listing"
    for required in composer.json README.md CHANGELOG.md LICENSE src/Time/ElapsedDuration.php src/Time/InvalidElapsedDuration.php; do
        grep -Fxq "$required" "$listing" || fail "$version archive omitted required path $required"
    done
    for forbidden in vendor/ composer.lock tests/ scripts/ .github/ .env auth.json .git/ .composer/; do
        if grep -Eq "(^|/)${forbidden//./\\.}" "$listing"; then
            fail "$version archive included forbidden path $forbidden"
        fi
    done
    tar -xOzf "$archive" composer.json >"$WORK_DIR/archive-$version-composer.json"
    php -r '
        $manifest = json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
        if (($manifest["name"] ?? null) !== "cjph96/php-core" || ($manifest["version"] ?? null) !== $argv[2]) {
            fwrite(STDERR, "archive manifest identity mismatch\n");
            exit(1);
        }
        if (($manifest["require"] ?? []) !== ["php" => "~8.5.0"] || isset($manifest["require-dev"])) {
            fwrite(STDERR, "archive runtime dependency contract mismatch\n");
            exit(1);
        }
    ' "$WORK_DIR/archive-$version-composer.json" "$version" || fail "$version archive manifest did not match the expected public package contract"
}

run_consumer_contract() {
    local project_dir="$1"
    local log_file="$2"
    local expected_identity="$3"

    if ! php "$PACKAGE_ROOT/scripts/distribution/verify-consumer.php" "$project_dir" "$expected_identity" >"$log_file" 2>&1; then
        cat "$log_file" >&2
        fail "consumer contract failed for $expected_identity"
    fi
}

for version in 0.1.0 0.1.1; do
    payload="$WORK_DIR/package-$version"
    copy_package_payload "$payload" "$version"
    archive="$ARTIFACT_DIR/cjph96-php-core-$version.tar.gz"
    tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - \
        -C "$payload" composer.json README.md CHANGELOG.md LICENSE src | gzip -n >"$archive"
    check_payload "$archive" "$version" "$OUTPUT_DIR/archive-$version.contents.txt"
    sha256sum "$archive" >"$OUTPUT_DIR/archive-$version.sha256"
    sha1sum "$archive" >"$OUTPUT_DIR/archive-$version.sha1"
done

php -r '
    $versions = ["0.1.0", "0.1.1"];
    $packages = [];
    foreach ($versions as $version) {
        $archive = $argv[1] . "/cjph96-php-core-" . $version . ".tar.gz";
        $manifestPath = $argv[2] . "/archive-" . $version . "-composer.json";
        $manifestContents = file_get_contents($manifestPath);
        $archivePath = realpath($archive);
        $sha256 = hash_file("sha256", $archive);
        $sha1 = hash_file("sha1", $archive);
        if (! is_string($manifestContents) || ! is_string($archivePath) || ! is_string($sha256) || ! is_string($sha1)) {
            throw new RuntimeException("Could not derive immutable fixture identity for " . $version);
        }
        $package = json_decode($manifestContents, true, 512, JSON_THROW_ON_ERROR);
        if (! is_array($package) || ($package["name"] ?? null) !== "cjph96/php-core" || ($package["version"] ?? null) !== $version) {
            throw new RuntimeException("Fixture archive manifest identity mismatch for " . $version);
        }
        $dist = [
            "type" => "tar",
            "url" => "file://" . $archivePath,
            "reference" => $sha256,
            "shasum" => $sha1,
        ];
        $package["dist"] = $dist;
        unset($package["source"]);
        $packages[] = $package;
        $identity = ["version" => $version, "sha256" => $sha256, "dist" => $dist];
        file_put_contents($argv[3] . "/dist-" . $version . ".identity.json", json_encode($identity, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . "\n");
    }
    $index = ["packages" => ["cjph96/php-core" => $packages]];
    file_put_contents($argv[4], json_encode($index, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . "\n");
' "$ARTIFACT_DIR" "$WORK_DIR" "$OUTPUT_DIR" "$PACKAGE_INDEX"

# Consumer A resolves v0.1.0 and stays pinned there while Consumer B advances.
CONSUMER_A="$WORK_DIR/consumer-a"
write_consumer_manifest "$CONSUMER_A" '^0.1'
cp "$CONSUMER_A/composer.json" "$OUTPUT_DIR/consumer-a.composer.json"
composer_run "$CONSUMER_A" "$OUTPUT_DIR/consumer-a-initial-install.log" update --no-interaction --prefer-dist --with cjph96/php-core:0.1.0 || {
    cat "$OUTPUT_DIR/consumer-a-initial-install.log" >&2
    fail 'Consumer A could not resolve the first fixture release'
}
cp "$CONSUMER_A/composer.lock" "$OUTPUT_DIR/consumer-a.lock"
run_consumer_contract "$CONSUMER_A" "$OUTPUT_DIR/consumer-a-contract.log" "$OUTPUT_DIR/dist-0.1.0.identity.json"

# A second root and cache prove lockfile reinstall in a separate clean environment.
CLEAN_CONSUMER_A="$WORK_DIR/consumer-a-clean"
mkdir -p "$CLEAN_CONSUMER_A"
cp "$OUTPUT_DIR/consumer-a.composer.json" "$CLEAN_CONSUMER_A/composer.json"
cp "$OUTPUT_DIR/consumer-a.lock" "$CLEAN_CONSUMER_A/composer.lock"
composer_run "$CLEAN_CONSUMER_A" "$OUTPUT_DIR/consumer-a-reinstall.log" install --no-interaction --prefer-dist || {
    cat "$OUTPUT_DIR/consumer-a-reinstall.log" >&2
    fail 'Consumer A could not reinstall from its saved lockfile in a clean environment'
}
cmp "$OUTPUT_DIR/consumer-a.lock" "$CLEAN_CONSUMER_A/composer.lock" || fail 'Consumer A lockfile changed during clean reinstall'
run_consumer_contract "$CLEAN_CONSUMER_A" "$OUTPUT_DIR/consumer-a-reinstall-contract.log" "$OUTPUT_DIR/dist-0.1.0.identity.json"

CONSUMER_B="$WORK_DIR/consumer-b"
write_consumer_manifest "$CONSUMER_B" '^0.1'
cp "$CONSUMER_B/composer.json" "$OUTPUT_DIR/consumer-b.composer.json"
composer_run "$CONSUMER_B" "$OUTPUT_DIR/consumer-b-initial-install.log" update --no-interaction --prefer-dist --with cjph96/php-core:0.1.0 || {
    cat "$OUTPUT_DIR/consumer-b-initial-install.log" >&2
    fail 'Consumer B could not install the earlier fixture release'
}
cp "$CONSUMER_B/composer.lock" "$OUTPUT_DIR/consumer-b-before-upgrade.lock"
run_consumer_contract "$CONSUMER_B" "$OUTPUT_DIR/consumer-b-before-upgrade-contract.log" "$OUTPUT_DIR/dist-0.1.0.identity.json"
composer_run "$CONSUMER_B" "$OUTPUT_DIR/consumer-b-upgrade.log" update cjph96/php-core --no-interaction --prefer-dist || {
    cat "$OUTPUT_DIR/consumer-b-upgrade.log" >&2
    fail 'Consumer B could not upgrade to the later fixture release'
}
cp "$CONSUMER_B/composer.lock" "$OUTPUT_DIR/consumer-b.lock"
run_consumer_contract "$CONSUMER_B" "$OUTPUT_DIR/consumer-b-contract.log" "$OUTPUT_DIR/dist-0.1.1.identity.json"
cmp "$OUTPUT_DIR/consumer-a.lock" "$CONSUMER_A/composer.lock" || fail 'Consumer A lockfile changed when Consumer B upgraded'

# Reinstall B's upgraded lockfile in another clean root with a fresh Composer home and cache.
CLEAN_CONSUMER_B="$WORK_DIR/consumer-b-clean"
mkdir -p "$CLEAN_CONSUMER_B"
cp "$OUTPUT_DIR/consumer-b.composer.json" "$CLEAN_CONSUMER_B/composer.json"
cp "$OUTPUT_DIR/consumer-b.lock" "$CLEAN_CONSUMER_B/composer.lock"
composer_run "$CLEAN_CONSUMER_B" "$OUTPUT_DIR/consumer-b-reinstall.log" install --no-interaction --prefer-dist || {
    cat "$OUTPUT_DIR/consumer-b-reinstall.log" >&2
    fail 'Consumer B could not reinstall from its upgraded lockfile in a clean environment'
}
cmp "$OUTPUT_DIR/consumer-b.lock" "$CLEAN_CONSUMER_B/composer.lock" || fail 'Consumer B lockfile changed during clean reinstall'
run_consumer_contract "$CLEAN_CONSUMER_B" "$OUTPUT_DIR/consumer-b-reinstall-contract.log" "$OUTPUT_DIR/dist-0.1.1.identity.json"

# Roll back B in a fresh environment by reinstalling its known-compatible earlier lockfile.
CLEAN_ROLLBACK_B="$WORK_DIR/consumer-b-rollback"
mkdir -p "$CLEAN_ROLLBACK_B"
cp "$OUTPUT_DIR/consumer-b.composer.json" "$CLEAN_ROLLBACK_B/composer.json"
cp "$OUTPUT_DIR/consumer-b-before-upgrade.lock" "$CLEAN_ROLLBACK_B/composer.lock"
composer_run "$CLEAN_ROLLBACK_B" "$OUTPUT_DIR/consumer-b-rollback.log" install --no-interaction --prefer-dist || {
    cat "$OUTPUT_DIR/consumer-b-rollback.log" >&2
    fail 'Consumer B could not roll back using its earlier lockfile in a clean environment'
}
run_consumer_contract "$CLEAN_ROLLBACK_B" "$OUTPUT_DIR/consumer-b-rollback-contract.log" "$OUTPUT_DIR/dist-0.1.0.identity.json"

# Each root manifest disables Packagist, so missing versions cannot silently fall back to public packages.
NEGATIVE_PHP="$WORK_DIR/negative-php"
write_consumer_manifest "$NEGATIVE_PHP" '^0.1' '~8.6.0'
cp "$NEGATIVE_PHP/composer.json" "$OUTPUT_DIR/negative-incompatible-php.composer.json"
if composer_run "$NEGATIVE_PHP" "$OUTPUT_DIR/negative-incompatible-php.log" update --no-interaction --prefer-dist; then
    fail 'incompatible PHP constraint unexpectedly resolved'
fi
grep -Eiq 'php .*8\.6|requires php|platform requirements' "$OUTPUT_DIR/negative-incompatible-php.log" || {
    cat "$OUTPUT_DIR/negative-incompatible-php.log" >&2
    fail 'incompatible PHP failure did not report the expected platform reason'
}

NEGATIVE_VERSION="$WORK_DIR/negative-version"
write_consumer_manifest "$NEGATIVE_VERSION" '0.1.99'
cp "$NEGATIVE_VERSION/composer.json" "$OUTPUT_DIR/negative-unavailable-version.composer.json"
if composer_run "$NEGATIVE_VERSION" "$OUTPUT_DIR/negative-unavailable-version.log" update --no-interaction --prefer-dist; then
    fail 'unavailable package version unexpectedly resolved'
fi
grep -Eiq '0\.1\.99|could not be found|no matching package' "$OUTPUT_DIR/negative-unavailable-version.log" || {
    cat "$OUTPUT_DIR/negative-unavailable-version.log" >&2
    fail 'unavailable-version failure did not identify the missing package version'
}

printf 'checkout_head=%s\n' "$(git -C "$PACKAGE_ROOT" rev-parse HEAD 2>/dev/null || printf 'unavailable')" >"$OUTPUT_DIR/identity.txt"
sha256sum "$PACKAGE_ROOT/composer.json" >>"$OUTPUT_DIR/identity.txt"
find "$PACKAGE_ROOT/src" -type f -name '*.php' -print | sort | while IFS= read -r source_file; do
    sha256sum "$source_file"
done >"$OUTPUT_DIR/source-files.sha256"
printf 'php=%s\n' "$(php --version | head -1)" >>"$OUTPUT_DIR/identity.txt"
printf 'composer=%s\n' "$(composer --version --no-ansi | head -1)" >>"$OUTPUT_DIR/identity.txt"
printf 'distribution-smoke=passed\n' >"$OUTPUT_DIR/result.txt"
printf 'Distribution fixtures passed. Evidence retained in %s\n' "$OUTPUT_DIR"
