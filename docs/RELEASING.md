# Releasing php-core

This document describes the selected distribution for `cjph96/php-core`. The public target is the GitHub repository `https://github.com/cjph96/php-core`, submitted to Packagist as `cjph96/php-core`. The first approved release content is the current package base plus `CJPH\Core\Time\ElapsedDuration` and its validation exception. The initial tag is `v0.1.0`.

## Release requirements

Before publishing, verify the authenticated GitHub account and repository owner, public visibility, candidate commit, MIT license and package contents. Inspect the actual repository protection and release/tag settings; this procedure requires operators to leave published tags untouched, but the documentation itself does not enforce tag immutability. Confirm that the Packagist package points to the approved GitHub repository and that anonymous consumers can install it. A local build or fixture repository does not prove either remote configuration.

Run the full `composer quality` command in the pinned development image. Set `OUTPUT_DIR` to an empty disposable directory outside the checkout when running `composer distribution-smoke`; retain its manifests, lockfiles, archive checksums, dependency logs, contract results and identity record with the release evidence. The test artifacts `0.1.0` and `0.1.1` are created only in that local disposable directory. Never push or publish them.

Create the first release with a new tag `v0.1.0` on the approved candidate commit. Do not add a fixed `version` field to the production `composer.json`; Composer derives the published package version from the tag. Do not force-update or reuse a published tag. A correction after publication uses a new version and tag.

Publication credentials belong in the host's approved secret manager or authentication flow. Never put credentials in source, workflow YAML, command arguments, fixture manifests, evidence output or logs. Consumer installation is public and must not require publication credentials. The quality workflow has read-only repository permissions and does not publish or use release credentials.

## Consumer upgrades and recovery

Each consuming project owns its dependency constraint and `composer.lock`. Install the package after it is listed on Packagist:

```sh
composer require cjph96/php-core:^0.1
```

Commit both Composer files. To evaluate a newer compatible version, update the dependency in a branch and run the consumer's tests before merging the new lockfile. A project that retains its earlier lockfile continues to install its earlier package version independently.

If an update causes a regression, restore the consumer's last known-good `composer.lock` from version control and run `composer install`. This restores the exact locked dependency graph. For a package defect, publish a corrected new version and tag; do not rewrite the affected tag. Before the first production release there is no prior published package to roll back to, so a consumer should retain its prior lockfile and defer the package adoption if a release is defective.

## Local distribution check

The disposable distribution check creates two deterministic local tar archives from the candidate package files and assigns them fixture-only versions in an explicit Composer package repository. Metadata pins each archive URL, SHA-256 reference and Composer SHA-1 checksum. Two independent consumer projects install and lock the earlier version; one upgrades to the later version while the other remains unchanged. Both locks are installed in new consumer roots with fresh Composer homes and caches, the upgraded consumer rolls back using its earlier lock, and each installed package is checked through the consumer's own autoloader. The test also checks archive contents and confirms that incompatible PHP and unavailable package-version constraints fail. Every fixture root disables Packagist fallback.

Run it with an evidence directory outside the package checkout:

```sh
OUTPUT_DIR=/absolute/path/to/disposable-evidence composer distribution-smoke
```

This local check does not establish GitHub ownership or visibility, Packagist ingestion, anonymous remote installation, remote CI success or publication.
