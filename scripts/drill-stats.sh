#!/usr/bin/env bash
#
# drill-stats.sh - Reports drill usage statistics
#
# Usage:
#   ./drill-stats.sh          # List all drills sorted by frequency
#   ./drill-stats.sh -a       # List all drills sorted by name (Alphabetical)
#   ./drill-stats.sh -d       # List all drills sorted by Last Date Used
#   ./drill-stats.sh [query]  # Search for specific drills
#

DB_FILE="${STATS_DB:-stats.db}"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database '$DB_FILE' not found."
    exit 1
fi

ARG="$1"
ORDER_BY="count DESC, last_date DESC"
WHERE_CLAUSE="1=1"

if [ "$ARG" == "-a" ]; then
    ORDER_BY="d.drill_name ASC"
elif [ "$ARG" == "-d" ]; then
    ORDER_BY="last_date DESC, count DESC"
elif [ -n "$ARG" ] && [[ "$ARG" != -* ]]; then
    WHERE_CLAUSE="d.drill_name LIKE '%$ARG%'"
fi

echo "=== Drill Usage Report ==="
sqlite3 -header -column "$DB_FILE" "
WITH stats AS (
    SELECT
        d.drill_name,
        COUNT(pd.event_id) as count,
        MAX(e.event_date) as last_date
    FROM drills d
    LEFT JOIN practice_drills pd ON d.drill_id = pd.drill_id
    LEFT JOIN events e ON pd.event_id = e.event_id
    WHERE $WHERE_CLAUSE
    GROUP BY d.drill_id, d.drill_name
)
SELECT
    drill_name as 'Drill Name',
    count as 'Times Used',
    COALESCE(last_date, 'Never') as 'Last Used'
FROM stats
ORDER BY $ORDER_BY;
"
