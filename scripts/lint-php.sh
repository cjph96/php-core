#!/usr/bin/env bash

set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
find "$package_root/src" "$package_root/scripts" "$package_root/tests" "$package_root/.php-cs-fixer.dist.php" -type f -name '*.php' -print0 \
    | xargs -0 -r -n1 php -l
