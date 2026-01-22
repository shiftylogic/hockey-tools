#!/usr/bin/env bash
#
# check-attendance.sh - Reports player or team attendance stats
#
# Usage: 
#   ./check-attendance.sh          # Team Summary
#   ./check-attendance.sh [query]  # Specific player (Name or Jersey #)
#

DB_FILE="${STATS_DB:-stats.db}"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database '$DB_FILE' not found."
    exit 1
fi

SEARCH_QUERY="$1"

if [ -z "$SEARCH_QUERY" ]; then
    # =========================================================================
    # TEAM SUMMARY
    # =========================================================================
    echo "=== Team Attendance Summary ==="
    sqlite3 -header -column "$DB_FILE" "
    WITH records AS (
        SELECT event_id, player_id, 1 as present FROM attendance
        UNION ALL
        SELECT event_id, player_id, 0 as present FROM absences
    )
    SELECT
        r.jersey_number as '#',
        r.player_name as 'Player',
        -- Overall
        printf('%.1f%%', 100.0 * SUM(rec.present) / COUNT(*)) as 'Total %',
        -- Practice
        printf('%.1f%%', 100.0 * SUM(CASE WHEN e.event_type='practice' THEN rec.present ELSE 0 END) / NULLIF(SUM(CASE WHEN e.event_type='practice' THEN 1 ELSE 0 END), 0)) as 'Prac %',
        -- Dryland
        printf('%.1f%%', 100.0 * SUM(CASE WHEN e.event_type='dryland' THEN rec.present ELSE 0 END) / NULLIF(SUM(CASE WHEN e.event_type='dryland' THEN 1 ELSE 0 END), 0)) as 'Dry %',
        -- Classroom
        printf('%.1f%%', 100.0 * SUM(CASE WHEN e.event_type='classroom' THEN rec.present ELSE 0 END) / NULLIF(SUM(CASE WHEN e.event_type='classroom' THEN 1 ELSE 0 END), 0)) as 'Class %'
    FROM roster r
    JOIN records rec ON r.player_id = rec.player_id
    JOIN events e ON rec.event_id = e.event_id
    GROUP BY r.player_id
    ORDER BY SUM(rec.present) * 1.0 / COUNT(*) DESC;
    "
else
    # =========================================================================
    # INDIVIDUAL PLAYER REPORT
    # =========================================================================
    
    # 1. Resolve Player ID
    if [[ "$SEARCH_QUERY" =~ ^[0-9]+$ ]]; then
        WHERE_CLAUSE="jersey_number = $SEARCH_QUERY"
    else
        WHERE_CLAUSE="player_name LIKE '%$SEARCH_QUERY%'"
    fi

    PLAYER_INFO=$(sqlite3 "$DB_FILE" "SELECT player_id, player_name, jersey_number FROM roster WHERE $WHERE_CLAUSE LIMIT 1;")

    if [ -z "$PLAYER_INFO" ]; then
        echo "Error: Player '$SEARCH_QUERY' not found."
        exit 1
    fi

    IFS='|' read -r PID NAME JERSEY <<< "$PLAYER_INFO"
    echo "=== Attendance Report: #$JERSEY $NAME ==="
    echo ""

    # 2. Stats Breakdown
    echo "--- Statistics ---"
    sqlite3 -header -column "$DB_FILE" "
    WITH records AS (
        SELECT event_id, player_id, 1 as present FROM attendance WHERE player_id = $PID
        UNION ALL
        SELECT event_id, player_id, 0 as present FROM absences WHERE player_id = $PID
    )
    SELECT
        e.event_type as 'Type',
        COUNT(*) as 'Total',
        SUM(rec.present) as 'Attended',
        COUNT(*) - SUM(rec.present) as 'Missed',
        printf('%.1f%%', 100.0 * SUM(rec.present) / COUNT(*)) as 'Rate'
    FROM events e
    JOIN records rec ON e.event_id = rec.event_id
    GROUP BY e.event_type
    UNION ALL
    SELECT
        'ALL EVENTS',
        COUNT(*),
        SUM(rec.present),
        COUNT(*) - SUM(rec.present),
        printf('%.1f%%', 100.0 * SUM(rec.present) / COUNT(*))
    FROM events e
    JOIN records rec ON e.event_id = rec.event_id;
    "
    echo ""

    # 3. List of Absences
    echo "--- Missed Events ---"
    sqlite3 -header -column "$DB_FILE" "
    SELECT
        e.event_date as 'Date',
        e.event_type as 'Type',
        UPPER(SUBSTR(ab.absence_type, 1, 1)) || SUBSTR(ab.absence_type, 2) as 'Reason',
        COALESCE(ab.note, '') as 'Note'
    FROM absences ab
    JOIN events e ON ab.event_id = e.event_id
    WHERE ab.player_id = $PID
    ORDER BY e.event_date DESC;
    "
fi
