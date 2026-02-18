#!/usr/bin/env bash
#
# compute-player-stats.sh - Calculates player statistics from the database
#

# Default values
DB_FILE=""
FILTER_TAG=""
FILTER_START_DATE=""
FILTER_END_DATE=""
FILTER_GAME_ID=""
FILTER_GAME_IDS=""
FILTER_OPPONENT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            FILTER_TAG="$2"
            shift 2
            ;;
        --start-date)
            FILTER_START_DATE="$2"
            shift 2
            ;;
        --end-date)
            FILTER_END_DATE="$2"
            shift 2
            ;;
        --game)
            FILTER_GAME_ID="$2"
            shift 2
            ;;
        --games)
            FILTER_GAME_IDS="$2"
            shift 2
            ;;
        --opponent)
            FILTER_OPPONENT="$2"
            shift 2
            ;;
        *)
            if [ -z "$DB_FILE" ]; then
                DB_FILE="$1"
            else
                echo "Error: Unknown argument or multiple database files specified: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

DB_FILE="${DB_FILE:-stats.db}"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database file '$DB_FILE' not found."
    exit 1
fi

# Construct WHERE clause for filtered_games
WHERE_CLAUSE="1=1"
JOIN_CLAUSE=""

if [ -n "$FILTER_TAG" ]; then
    JOIN_CLAUSE="$JOIN_CLAUSE JOIN game_tag_mapping gtm ON g.game_id = gtm.game_id JOIN game_tags gt ON gtm.tag_id = gt.tag_id"
    WHERE_CLAUSE="$WHERE_CLAUSE AND gt.tag_name = '$FILTER_TAG'"
fi

if [ -n "$FILTER_START_DATE" ]; then
    WHERE_CLAUSE="$WHERE_CLAUSE AND g.game_date >= '$FILTER_START_DATE'"
fi

if [ -n "$FILTER_END_DATE" ]; then
    WHERE_CLAUSE="$WHERE_CLAUSE AND g.game_date <= '$FILTER_END_DATE'"
fi

if [ -n "$FILTER_GAME_ID" ]; then
    WHERE_CLAUSE="$WHERE_CLAUSE AND g.game_id = $FILTER_GAME_ID"
fi

if [ -n "$FILTER_GAME_IDS" ]; then
    GAME_ID_CONDITION=""
    IFS=',' read -ra PARTS <<< "$FILTER_GAME_IDS"
    for part in "${PARTS[@]}"; do
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            for ((i=start; i<=end; i++)); do
                if [ -n "$GAME_ID_CONDITION" ]; then
                    GAME_ID_CONDITION="$GAME_ID_CONDITION OR "
                fi
                GAME_ID_CONDITION="${GAME_ID_CONDITION}g.game_id = $i"
            done
        else
            if [ -n "$GAME_ID_CONDITION" ]; then
                GAME_ID_CONDITION="$GAME_ID_CONDITION OR "
            fi
            GAME_ID_CONDITION="${GAME_ID_CONDITION}g.game_id = $part"
        fi
    done
    WHERE_CLAUSE="$WHERE_CLAUSE AND ($GAME_ID_CONDITION)"
fi

if [ -n "$FILTER_OPPONENT" ]; then
    WHERE_CLAUSE="$WHERE_CLAUSE AND g.opponent_name LIKE '%$FILTER_OPPONENT%'"
fi

sql_query="
WITH 
filtered_games AS (
    SELECT g.game_id
    FROM games g
    $JOIN_CLAUSE
    WHERE $WHERE_CLAUSE
),
games_played AS (
    SELECT player_id, COUNT(DISTINCT gr.game_id) as gp
    FROM game_roster gr
    JOIN filtered_games fg ON gr.game_id = fg.game_id
    WHERE position != 'scratch'
    GROUP BY player_id
),
goals AS (
    SELECT scorer_id as player_id, COUNT(*) as goals
    FROM goals_for gf
    JOIN filtered_games fg ON gf.game_id = fg.game_id
    GROUP BY scorer_id
),
assists AS (
    SELECT player_id, SUM(cnt) as assists
    FROM (
        SELECT assist1_id as player_id, COUNT(*) as cnt FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE assist1_id IS NOT NULL GROUP BY assist1_id
        UNION ALL
        SELECT assist2_id as player_id, COUNT(*) as cnt FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE assist2_id IS NOT NULL GROUP BY assist2_id
    )
    GROUP BY player_id
),
penalties_calc AS (
    SELECT p.player_id, SUM(pt.penalty_length) as pim
    FROM penalties p
    JOIN penalty_types pt ON p.penalty_type_id = pt.penalty_type_id
    JOIN filtered_games fg ON p.game_id = fg.game_id
    GROUP BY p.player_id
),
plus_minus_plus AS (
    SELECT player_id, COUNT(*) as plus
    FROM (
        SELECT scorer_id as player_id FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE goal_type != 'power_play'
        UNION ALL SELECT assist1_id FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE goal_type != 'power_play' AND assist1_id IS NOT NULL
        UNION ALL SELECT assist2_id FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE goal_type != 'power_play' AND assist2_id IS NOT NULL
        UNION ALL SELECT extra_skater1_id FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE goal_type != 'power_play' AND extra_skater1_id IS NOT NULL
        UNION ALL SELECT extra_skater2_id FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE goal_type != 'power_play' AND extra_skater2_id IS NOT NULL
        UNION ALL SELECT extra_skater3_id FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE goal_type != 'power_play' AND extra_skater3_id IS NOT NULL
        UNION ALL SELECT extra_skater4_id FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE goal_type != 'power_play' AND extra_skater4_id IS NOT NULL
    )
    GROUP BY player_id
),
plus_minus_minus AS (
    SELECT player_id, COUNT(*) as minus
    FROM (
        SELECT on_ice1_id as player_id FROM goals_against ga JOIN filtered_games fg ON ga.game_id = fg.game_id WHERE goal_type != 'shorthanded' AND on_ice1_id IS NOT NULL
        UNION ALL SELECT on_ice2_id FROM goals_against ga JOIN filtered_games fg ON ga.game_id = fg.game_id WHERE goal_type != 'shorthanded' AND on_ice2_id IS NOT NULL
        UNION ALL SELECT on_ice3_id FROM goals_against ga JOIN filtered_games fg ON ga.game_id = fg.game_id WHERE goal_type != 'shorthanded' AND on_ice3_id IS NOT NULL
        UNION ALL SELECT on_ice4_id FROM goals_against ga JOIN filtered_games fg ON ga.game_id = fg.game_id WHERE goal_type != 'shorthanded' AND on_ice4_id IS NOT NULL
        UNION ALL SELECT on_ice5_id FROM goals_against ga JOIN filtered_games fg ON ga.game_id = fg.game_id WHERE goal_type != 'shorthanded' AND on_ice5_id IS NOT NULL
        UNION ALL SELECT on_ice6_id FROM goals_against ga JOIN filtered_games fg ON ga.game_id = fg.game_id WHERE goal_type != 'shorthanded' AND on_ice6_id IS NOT NULL
    )
    GROUP BY player_id
),
team_totals AS (
    SELECT 
        (SELECT COUNT(*) FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id) as total_goals,
        (SELECT COUNT(*) FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE assist1_id IS NOT NULL) +
        (SELECT COUNT(*) FROM goals_for gf JOIN filtered_games fg ON gf.game_id = fg.game_id WHERE assist2_id IS NOT NULL) as total_assists
)
SELECT 
    r.jersey_number as '#',
    r.player_name as 'Player',
    r.primary_position as 'Pos',
    COALESCE(gp.gp, 0) as GP,
    COALESCE(g.goals, 0) as G,
    COALESCE(a.assists, 0) as A,
    (COALESCE(g.goals, 0) + COALESCE(a.assists, 0)) as PTS,
    printf('%.2f', CAST(COALESCE(g.goals, 0) as FLOAT) / gp.gp) as GPG,
    printf('%.2f', CAST(COALESCE(a.assists, 0) as FLOAT) / gp.gp) as APG,
    printf('%.2f', CAST((COALESCE(g.goals, 0) + COALESCE(a.assists, 0)) as FLOAT) / gp.gp) as PPG,
    printf('%.1f', (CAST(COALESCE(g.goals, 0) as FLOAT) / NULLIF((SELECT total_goals FROM team_totals), 0)) * 100) as '%G',
    printf('%.1f', (CAST(COALESCE(a.assists, 0) as FLOAT) / NULLIF((SELECT total_assists FROM team_totals), 0)) * 100) as '%A',
    printf('%.1f', (CAST((COALESCE(g.goals, 0) + COALESCE(a.assists, 0)) as FLOAT) / NULLIF((SELECT total_goals + total_assists FROM team_totals), 0)) * 100) as '%P',
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