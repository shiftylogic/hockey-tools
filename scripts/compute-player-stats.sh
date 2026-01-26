#!/usr/bin/env bash
#
# compute-player-stats.sh - Calculates player statistics from the database
#

DB_FILE="${1:-stats.db}"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database file '$DB_FILE' not found."
    exit 1
fi

sql_query="
WITH 
games_played AS (
    SELECT player_id, COUNT(DISTINCT game_id) as gp
    FROM game_roster
    WHERE position != 'scratch'
    GROUP BY player_id
),
goals AS (
    SELECT scorer_id as player_id, COUNT(*) as goals
    FROM goals_for
    GROUP BY scorer_id
),
assists AS (
    SELECT player_id, SUM(cnt) as assists
    FROM (
        SELECT assist1_id as player_id, COUNT(*) as cnt FROM goals_for WHERE assist1_id IS NOT NULL GROUP BY assist1_id
        UNION ALL
        SELECT assist2_id as player_id, COUNT(*) as cnt FROM goals_for WHERE assist2_id IS NOT NULL GROUP BY assist2_id
    )
    GROUP BY player_id
),
penalties_calc AS (
    SELECT p.player_id, SUM(pt.penalty_length) as pim
    FROM penalties p
    JOIN penalty_types pt ON p.penalty_type_id = pt.penalty_type_id
    GROUP BY p.player_id
),
plus_minus_plus AS (
    SELECT player_id, COUNT(*) as plus
    FROM (
        SELECT scorer_id as player_id FROM goals_for WHERE goal_type != 'power_play'
        UNION ALL SELECT assist1_id FROM goals_for WHERE goal_type != 'power_play' AND assist1_id IS NOT NULL
        UNION ALL SELECT assist2_id FROM goals_for WHERE goal_type != 'power_play' AND assist2_id IS NOT NULL
        UNION ALL SELECT extra_skater1_id FROM goals_for WHERE goal_type != 'power_play' AND extra_skater1_id IS NOT NULL
        UNION ALL SELECT extra_skater2_id FROM goals_for WHERE goal_type != 'power_play' AND extra_skater2_id IS NOT NULL
        UNION ALL SELECT extra_skater3_id FROM goals_for WHERE goal_type != 'power_play' AND extra_skater3_id IS NOT NULL
        UNION ALL SELECT extra_skater4_id FROM goals_for WHERE goal_type != 'power_play' AND extra_skater4_id IS NOT NULL
    )
    GROUP BY player_id
),
plus_minus_minus AS (
    SELECT player_id, COUNT(*) as minus
    FROM (
        SELECT on_ice1_id as player_id FROM goals_against WHERE goal_type != 'shorthanded' AND on_ice1_id IS NOT NULL
        UNION ALL SELECT on_ice2_id FROM goals_against WHERE goal_type != 'shorthanded' AND on_ice2_id IS NOT NULL
        UNION ALL SELECT on_ice3_id FROM goals_against WHERE goal_type != 'shorthanded' AND on_ice3_id IS NOT NULL
        UNION ALL SELECT on_ice4_id FROM goals_against WHERE goal_type != 'shorthanded' AND on_ice4_id IS NOT NULL
        UNION ALL SELECT on_ice5_id FROM goals_against WHERE goal_type != 'shorthanded' AND on_ice5_id IS NOT NULL
        UNION ALL SELECT on_ice6_id FROM goals_against WHERE goal_type != 'shorthanded' AND on_ice6_id IS NOT NULL
    )
    GROUP BY player_id
)
SELECT 
    r.jersey_number as '#',
    r.player_name as 'Player',
    r.primary_position as 'Pos',
    COALESCE(gp.gp, 0) as GP,
    COALESCE(g.goals, 0) as G,
    COALESCE(a.assists, 0) as A,
    (COALESCE(g.goals, 0) + COALESCE(a.assists, 0)) as PTS,
    (COALESCE(pmp.plus, 0) - COALESCE(pmm.minus, 0)) as '+/-',
    COALESCE(pim.pim, 0) as PIM
FROM roster r
LEFT JOIN games_played gp ON r.player_id = gp.player_id
LEFT JOIN goals g ON r.player_id = g.player_id
LEFT JOIN assists a ON r.player_id = a.player_id
LEFT JOIN penalties_calc pim ON r.player_id = pim.player_id
LEFT JOIN plus_minus_plus pmp ON r.player_id = pmp.player_id
LEFT JOIN plus_minus_minus pmm ON r.player_id = pmm.player_id
WHERE GP > 0
ORDER BY PTS DESC, G DESC, GP ASC;
"

sqlite3 -header -column "$DB_FILE" "$sql_query"
