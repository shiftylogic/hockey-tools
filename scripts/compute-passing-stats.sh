#!/usr/bin/env bash
#
# compute-passing-stats.sh - Replicates the Passing-Overall.csv report
#

DB_FILE="${1:-stats.db}"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database file '$DB_FILE' not found."
    exit 1
fi

# Define the query
sql_query="
WITH raw_data AS (
    SELECT
        CASE
            WHEN t.tag_name = 'tournament' THEN 'Tourney'
            WHEN t.tag_name = 'league' THEN 'League'
            WHEN t.tag_name = 'exhibition' THEN 'Exhibition'
            WHEN t.tag_name = 'tiering' THEN 'Tiering'
        END as Type,
        p.game_id,
        p.period,
        p.attempts,
        p.completed
    FROM team_passing_stats p
    JOIN game_tag_mapping m ON p.game_id = m.game_id
    JOIN game_tags t ON m.tag_id = t.tag_id
    WHERE t.tag_name IN ('league', 'tournament', 'exhibition', 'tiering')
),
stats AS (
    SELECT
        Type,
        COUNT(DISTINCT game_id) as Games,
        SUM(attempts) as Att,
        SUM(completed) as Comp,
        SUM(CASE WHEN period=1 THEN attempts ELSE 0 END) as P1_A,
        SUM(CASE WHEN period=1 THEN completed ELSE 0 END) as P1_C,
        SUM(CASE WHEN period=2 THEN attempts ELSE 0 END) as P2_A,
        SUM(CASE WHEN period=2 THEN completed ELSE 0 END) as P2_C,
        SUM(CASE WHEN period=3 THEN attempts ELSE 0 END) as P3_A,
        SUM(CASE WHEN period=3 THEN completed ELSE 0 END) as P3_C,
        SUM(CASE WHEN period=4 THEN attempts ELSE 0 END) as OT_A,
        SUM(CASE WHEN period=4 THEN completed ELSE 0 END) as OT_C
    FROM raw_data
    GROUP BY Type
),
totals AS (
    SELECT
        'Totals' as Type,
        SUM(Games) as Games,
        SUM(Att) as Att,
        SUM(Comp) as Comp,
        SUM(P1_A) as P1_A, SUM(P1_C) as P1_C,
        SUM(P2_A) as P2_A, SUM(P2_C) as P2_C,
        SUM(P3_A) as P3_A, SUM(P3_C) as P3_C,
        SUM(OT_A) as OT_A, SUM(OT_C) as OT_C
    FROM stats
),
combined AS (
    SELECT * FROM stats
    UNION ALL
    SELECT * FROM totals
)
SELECT
    Type,
    Att,
    Comp,
    printf('%.1f%%', (CAST(Comp AS FLOAT) / Att) * 100) as '%',
    P1_A, P1_C, printf('%.1f%%', (CAST(P1_C AS FLOAT) / NULLIF(P1_A, 0)) * 100) as 'P1 %',
    P2_A, P2_C, printf('%.1f%%', (CAST(P2_C AS FLOAT) / NULLIF(P2_A, 0)) * 100) as 'P2 %',
    P3_A, P3_C, printf('%.1f%%', (CAST(P3_C AS FLOAT) / NULLIF(P3_A, 0)) * 100) as 'P3 %',
    OT_A, OT_C, printf('%.1f%%', (CAST(OT_C AS FLOAT) / NULLIF(OT_A, 0)) * 100) as 'OT %',
    Games,
    printf('%.1f', CAST(Att AS FLOAT) / Games) as APG,
    printf('%.1f', CAST(Comp AS FLOAT) / Games) as CPG
FROM combined
ORDER BY 
    CASE Type 
        WHEN 'League' THEN 1 
        WHEN 'Tourney' THEN 2 
        WHEN 'Exhibition' THEN 3 
        WHEN 'Tiering' THEN 4 
        ELSE 5 
    END;
"

# Execute with formatted output
sqlite3 -header -column "$DB_FILE" "$sql_query" | sed 's/%  /   /g' # Minor spacing adjustment if needed
