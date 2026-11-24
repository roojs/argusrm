#!/usr/bin/env bash
# Emit PE paths from a server sqlite programs table (for Windows probes).
#
# Usage:
#   tests/programs-authenticode-export-paths.sh DB [limit]              # path per line
#   tests/programs-authenticode-export-paths.sh DB [limit] --csv       # path + registry publisher
set -euo pipefail
DB="${1:?sqlite path required}"
LIMIT="${2:-500}"
MODE="${3:-}"
WHERE="install_location GLOB '*.exe' OR install_location GLOB '*.EXE'
   OR install_location GLOB '*.dll' OR install_location GLOB '*.DLL'"
if [[ "$MODE" == "--csv" ]]; then
	sqlite3 -batch -header -csv "$DB" "
SELECT install_location,
       source,
       name,
       publisher AS registry_publisher
FROM programs
WHERE $WHERE
  AND install_location != ''
GROUP BY install_location
ORDER BY install_location
LIMIT $LIMIT;
"
	exit 0
fi
sqlite3 -batch "$DB" "
SELECT DISTINCT install_location
FROM programs
WHERE $WHERE
ORDER BY install_location
LIMIT $LIMIT;
"