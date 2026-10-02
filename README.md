# php-core

A small, independently versioned Composer library for product-approved, reusable technical primitives. Its first value object is an elapsed duration selected for Core ownership, with Booking Engine inheritance planned; that planned use is not evidence of implemented consumer adoption.

## Package contract

- Composer package: `cjph96/php-core`
- Namespace: `CJPH\Core\`, mapped to `src/`
- Supported PHP branch: `~8.5.0`; the development image runs PHP 8.5.11
- Runtime package dependencies: none
- Additional runtime extensions: none
- License: MIT, copyright Cristian J. Pérez Hernández

## Elapsed duration

`CJPH\Core\Time\ElapsedDuration` is a concrete, immutable, non-final readonly value that stores a non-negative integer number of seconds. It accepts `0` through `PHP_INT_MAX` and exposes the exact integer through `seconds(): int`. `equals(self $other): bool` compares seconds, including between a base value and a consumer subtype.

Negative values throw `CJPH\Core\Time\InvalidElapsedDuration`, a final subclass of PHP's `InvalidArgumentException`. The exception message is diagnostic and is not a stable API. The typed constructor is declared in a strict-types source file, but weakly typed callers may still pass coercible scalars; input adapters must validate external data.

Consumers may define readonly subclasses that validate local creation rules before calling the parent constructor. For example, a business duration may reject zero while the Core value continues to accept it. Subclasses inherit final `seconds()` and `equals()` methods and must not add value-defining state that needs different equality semantics. Business rules and their errors remain in the owning service. This extension surface is intended for planned compatibility and does not claim a production Booking Engine subtype or release.

Booking and Identity entities, identifiers with business meaning, authorization, ORM models, migrations, framework adapters and persistence guarantees belong to their owning services. Each primitive needs justified use cases and an approved behavior contract; planned consumer use does not prove implemented adoption. This package is not a deployed service and its installation smoke check does not prove tenant isolation, authorization or booking correctness.

## Development

Build the pinned development environment from this directory:

```sh
docker build -t php-core-dev .
docker run --rm -v "$PWD:/workspace" -w /workspace php-core-dev composer install
```

The image uses PHP 8.5.11 and Composer 2.10.3. Its installed DOM, mbstring, XML and tokenizer extensions plus `unzip` support development tools; they are not package runtime requirements. Composer is downloaded by exact version and checked against its published SHA-256 digest.

Run checks in the same container:

```sh
docker run --rm -v "$PWD:/workspace" -w /workspace php-core-dev composer quality
```

Individual commands are available as Composer scripts: `check:manifest`, `test`, `lint`, `analyse`, `format:check`, `boundaries`, `boundary-probes`, `architecture`, `security:audit`, `consumer-smoke` and `distribution-smoke`. `format:fix` applies the configured formatter. The tests cover boundary controls and the elapsed-duration contract. These commands run in the development container, where `xargs -r` is provided by the Linux userland.

The `boundaries` script inspects all PHP files under `src/`, rejects qualified references to other namespaces and known service-owned business types, and requires an empty production `require` section (apart from the PHP platform constraint). It is a static guard, not a proof of semantic purity. `boundary-probes` sends clean, prohibited-source, HTTP-contract, business-type and prohibited-runtime-dependency fixtures through the same guard. Deptrac also scans future source files for dependency direction. Development tools are locked in `composer.lock` and are excluded from consumer installations using `--no-dev`.

`consumer-smoke` creates a clean temporary PHP project, resolves this local package explicitly as `dev-main`, installs with `--no-dev`, and checks the generated PSR-4 mapping, installed package graph, and duration behavior through the consumer's own `vendor/autoload.php`. The consumer fixture defines a readonly positive-duration subtype to exercise the extension contract. Set `OUTPUT_DIR=/absolute/path` to retain its consumer manifest, lockfile and logs; otherwise it creates a temporary evidence directory and prints its path.

`distribution-smoke` is a separate check because it needs an evidence directory. It installs and upgrades checksummed local tar fixtures through explicit Composer package metadata, then repeats locked installs in fresh consumer roots and caches:

```sh
OUTPUT_DIR=/absolute/path/to/disposable-evidence composer distribution-smoke
```

## Versioning and installation

This package is versioned independently from Booking and every consumer chooses and locks its own version. The selected public distribution is the GitHub repository `cjph96/php-core` indexed by Packagist as `cjph96/php-core`. The initial release candidate is `v0.1.0`; publication and anonymous installation are confirmed separately from this local candidate.

After the package is available on Packagist, install it in a consumer with:

```sh
composer require cjph96/php-core:^0.1
```

Commit the consumer's `composer.json` and `composer.lock`. A consumer can then reinstall the exact resolved package with `composer install`; each consumer controls when it updates. The initial 0.x line may make incompatible changes between minor versions, so review the changelog and test upgrades before changing the constraint or lockfile. Public API additions require a concrete shared use case and documented behavior.

Never move or overwrite a published tag. For an incompatible artifact or consumer regression, restore the last known-good consumer lockfile and use the recovery steps in [`docs/RELEASING.md`](docs/RELEASING.md). The distribution smoke check uses disposable local fixture artifacts; its fixture versions are not production releases.
