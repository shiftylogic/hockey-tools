#!/usr/bin/env bash
#
# Copyright (c) 2025-present Robert Anderson.
# SPDX-License-Identifier: MIT
#
# ingest-csv-data.sh - Ingests CSV data into the hockey stats database
#
# Re-architected for performance:
# - Uses SQLite .import for bulk loading
# - Performs data cleaning and validation via SQL sets
# - Single transaction execution
#

set -e

DB_FILE="${1:-stats.db}"
DATA_DIR="${DATA_DIR:-./.data}"

if ! command -v sqlite3 &> /dev/null;
    then
    echo "Error: sqlite3 command not found."
    exit 1
fi

echo "Ingesting CSV data into: $DB_FILE"

# 1. Pre-process CSVs to remove Carriage Returns (CR) typical in Excel exports
#    We create clean temp files to ensure fast, bulk import works correctly.
mkdir -p ./.tmp_ingest
clean_roster="./.tmp_ingest/roster.csv"
clean_games="./.tmp_ingest/games.csv"
clean_goals_for="./.tmp_ingest/goals_for.csv"
clean_goals_against="./.tmp_ingest/goals_against.csv"
clean_penalties="./.tmp_ingest/penalties.csv"

tr -d '\r' < "$DATA_DIR/roster.csv" > "$clean_roster"
tr -d '\r' < "$DATA_DIR/Games-Games.csv" > "$clean_games"
tr -d '\r' < "$DATA_DIR/Goals For-For.csv" > "$clean_goals_for"
tr -d '\r' < "$DATA_DIR/Goals Against-Against.csv" > "$clean_goals_against"
tr -d '\r' < "$DATA_DIR/Penalties-Table 1.csv" > "$clean_penalties"

trap "rm -rf ./.tmp_ingest" EXIT

# 2. Execute Database Operations
sqlite3 "$DB_FILE" <<EOF
PRAGMA foreign_keys = OFF; -- Disable for bulk load, re-enable check later
PRAGMA synchronous = OFF;  -- Speed up bulk writes

-- ============================================================================
-- 1. SCHEMA DEFINITION
-- ============================================================================
DROP TABLE IF EXISTS shifts;
DROP TABLE IF EXISTS faceoffs;
DROP TABLE IF EXISTS saves;
DROP TABLE IF EXISTS player_changes;
DROP TABLE IF EXISTS giveaways;
DROP TABLE IF EXISTS takeaways;
DROP TABLE IF EXISTS blocks;
DROP TABLE IF EXISTS passes;
DROP TABLE IF EXISTS shots;
DROP TABLE IF EXISTS penalties;
DROP TABLE IF EXISTS goals_against;
DROP TABLE IF EXISTS goals_for;
DROP TABLE IF EXISTS game_tag_mapping;
DROP TABLE IF EXISTS game_tags;
DROP TABLE IF EXISTS game_roster;
DROP TABLE IF EXISTS roster;
DROP TABLE IF EXISTS penalty_types;
DROP TABLE IF EXISTS games;

CREATE TABLE games (
    game_id INTEGER PRIMARY KEY,
    game_date TEXT NOT NULL,
    game_time_minutes INTEGER NOT NULL,
    period1_length INTEGER NOT NULL,
    period1_clock_type TEXT NOT NULL CHECK (period1_clock_type IN ('stop', 'run')),
    period2_length INTEGER NOT NULL,
    period2_clock_type TEXT NOT NULL CHECK (period2_clock_type IN ('stop', 'run')),
    period3_length INTEGER NOT NULL,
    period3_clock_type TEXT NOT NULL CHECK (period3_clock_type IN ('stop', 'run')),
    period4_length INTEGER,
    period4_clock_type TEXT CHECK (period4_clock_type IN ('stop', 'run')),
    has_shootout INTEGER NOT NULL DEFAULT 0 CHECK (has_shootout IN (0, 1)),
    our_score INTEGER NOT NULL DEFAULT 0,
    their_score INTEGER NOT NULL DEFAULT 0,
    opponent_name TEXT
);

CREATE TABLE game_tags (
    tag_id INTEGER PRIMARY KEY,
    tag_name TEXT NOT NULL UNIQUE
);

CREATE TABLE game_tag_mapping (
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    tag_id INTEGER NOT NULL REFERENCES game_tags(tag_id),
    PRIMARY KEY (game_id, tag_id)
);

CREATE TABLE roster (
    player_id INTEGER PRIMARY KEY,
    jersey_number INTEGER NOT NULL UNIQUE,
    player_name TEXT NOT NULL,
    primary_position TEXT NOT NULL CHECK (primary_position IN ('center', 'forward', 'defense', 'goalie')),
    secondary_positions TEXT,
    birth_year INTEGER NOT NULL,
    handedness TEXT NOT NULL CHECK (handedness IN ('left', 'right'))
);

CREATE TABLE penalty_types (
    penalty_type_id INTEGER PRIMARY KEY,
    penalty_name TEXT NOT NULL,
    penalty_category TEXT NOT NULL CHECK (penalty_category IN ('minor', 'major', 'misconduct', 'game_misconduct', 'match')),
    penalty_length INTEGER NOT NULL
);

CREATE TABLE game_roster (
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    position TEXT NOT NULL CHECK (position IN ('forward', 'center', 'defense', 'goalie', 'scratch')),
    code TEXT NOT NULL,
    note TEXT,
    PRIMARY KEY (game_id, player_id)
);
CREATE INDEX idx_game_roster_game ON game_roster(game_id);
CREATE INDEX idx_game_roster_position ON game_roster(position);

CREATE TABLE goals_for (
    goal_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    scorer_id INTEGER NOT NULL REFERENCES roster(player_id),
    assist1_id INTEGER REFERENCES roster(player_id),
    assist2_id INTEGER REFERENCES roster(player_id),
    extra_skater1_id INTEGER REFERENCES roster(player_id),
    extra_skater2_id INTEGER REFERENCES roster(player_id),
    extra_skater3_id INTEGER REFERENCES roster(player_id),
    extra_skater4_id INTEGER REFERENCES roster(player_id),
    goal_type TEXT NOT NULL CHECK (goal_type IN ('power_play', 'shorthanded', 'even_strength', 'shootout', 'penalty_shot')),
    empty_net INTEGER NOT NULL DEFAULT 0 CHECK (empty_net IN (0, 1))
);

CREATE TABLE goals_against (
    goal_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    on_ice1_id INTEGER REFERENCES roster(player_id),
    on_ice2_id INTEGER REFERENCES roster(player_id),
    on_ice3_id INTEGER REFERENCES roster(player_id),
    on_ice4_id INTEGER REFERENCES roster(player_id),
    on_ice5_id INTEGER REFERENCES roster(player_id),
    on_ice6_id INTEGER REFERENCES roster(player_id),
    goal_type TEXT NOT NULL CHECK (goal_type IN ('power_play', 'shorthanded', 'even_strength', 'shootout', 'penalty_shot'))
);

CREATE TABLE penalties (
    penalty_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    player_id INTEGER REFERENCES roster(player_id),
    penalty_type_id INTEGER NOT NULL REFERENCES penalty_types(penalty_type_id),
    served_by_id INTEGER REFERENCES roster(player_id),
    notes TEXT(255)
);

-- Placeholder tables
CREATE TABLE shots (shot_id INTEGER PRIMARY KEY, game_id INTEGER, period INTEGER, time_seconds INTEGER, player_id INTEGER, result TEXT, origin_zone INTEGER);
CREATE TABLE passes (pass_id INTEGER PRIMARY KEY, game_id INTEGER, period INTEGER, time_seconds INTEGER, player_id INTEGER, target_player_id INTEGER, result TEXT, origin_zone TEXT);
CREATE TABLE blocks (block_id INTEGER PRIMARY KEY, game_id INTEGER, period INTEGER, time_seconds INTEGER, player_id INTEGER, origin_zone INTEGER);
CREATE TABLE takeaways (takeaway_id INTEGER PRIMARY KEY, game_id INTEGER, period INTEGER, time_seconds INTEGER, player_id INTEGER, origin_zone TEXT);
CREATE TABLE giveaways (giveaway_id INTEGER PRIMARY KEY, game_id INTEGER, period INTEGER, time_seconds INTEGER, player_id INTEGER, origin_zone TEXT);
CREATE TABLE player_changes (change_id INTEGER PRIMARY KEY, game_id INTEGER, period INTEGER, time_seconds INTEGER, incoming_id INTEGER, outgoing_id INTEGER);
CREATE TABLE saves (save_id INTEGER PRIMARY KEY, game_id INTEGER, period INTEGER, time_seconds INTEGER, goalie_id INTEGER);
CREATE TABLE faceoffs (faceoff_id INTEGER PRIMARY KEY, game_id INTEGER, period INTEGER, time_seconds INTEGER, player_id INTEGER, win_loss TEXT, extra1_id INTEGER, extra2_id INTEGER, extra3_id INTEGER, extra4_id INTEGER, extra5_id INTEGER);
CREATE TABLE shifts (shift_id INTEGER PRIMARY KEY, game_id INTEGER, player_id INTEGER, period INTEGER, start_seconds INTEGER, end_seconds INTEGER);


-- ============================================================================
-- 2. SEED DATA
-- ============================================================================
INSERT INTO game_tags (tag_name) VALUES ('PNAHA'), ('league'), ('tournament'), ('exhibition'), ('Canada'), ('tiering'), ('scrimmage');

INSERT INTO penalty_types (penalty_name, penalty_category, penalty_length) VALUES
    ('body-checking', 'minor', 2), ('body-checking', 'major', 5),
    ('slashing', 'minor', 2), ('slashing', 'major', 5),
    ('tripping', 'minor', 2), ('tripping', 'major', 5),
    ('hooking', 'minor', 2), ('hooking', 'major', 5),
    ('interference', 'minor', 2), ('interference', 'major', 5),
    ('holding', 'minor', 2), ('holding', 'major', 5),
    ('high-sticking', 'minor', 2), ('high-sticking', 'major', 5),
    ('cross-checking', 'minor', 2), ('cross-checking', 'major', 5),
    ('charging', 'minor', 2), ('charging', 'major', 5),
    ('elbowing', 'minor', 2), ('elbowing', 'major', 5),
    ('roughing', 'minor', 2), ('roughing', 'major', 5),
    ('delay-of-game', 'minor', 2), ('too-many-men', 'minor', 2),
    ('bench', 'minor', 2), ('unknown', 'minor', 2),
    ('checking-from-behind', 'minor', 2), ('checking-from-behind', 'major', 5),
    ('head-contact', 'minor', 2), ('head-contact', 'major', 5),
    ('fighting', 'major', 5), ('kicking', 'major', 5),
    ('kneeing', 'minor', 2), ('kneeing', 'major', 5),
    ('spearing', 'major', 5), ('unsportsmanlike', 'minor', 2),
    ('unsportsmanlike', 'major', 5), ('unsportsmanlike', 'misconduct', 10),
    ('misconduct', 'misconduct', 10), ('game-misconduct', 'misconduct', 10);

-- ============================================================================
-- 3. IMPORT & TRANSFORM
-- ============================================================================

-- A. Roster
-- ------------------------
CREATE TEMP TABLE imp_roster (jersey, name, pos, sec_pos, year, hand);
.mode csv
.import "$clean_roster" imp_roster

INSERT INTO roster (jersey_number, player_name, primary_position, secondary_positions, birth_year, handedness)
SELECT 
    CAST(jersey AS INTEGER), name, pos, 
    NULLIF(sec_pos, ''), 
    CAST(year AS INTEGER), hand
FROM imp_roster
WHERE jersey != 'jersey_number' AND jersey IS NOT NULL AND jersey != '';

-- B. Games & Game Roster
-- ------------------------
-- Define explicit columns to match CSV structure exactly for .import
CREATE TEMP TABLE imp_games (
    ID, Tag, Date, Time, Opponent, For, Against, x1, x2,
    g8, g31, x3, 
    d6, d19, d47, d81, d88, d89, x4, 
    f7, f16, f18, f22, f24, f30, f34, f86, f90, f97
);
.import "$clean_games" imp_games

-- Clean up header row if imported
DELETE FROM imp_games WHERE ID = 'ID';

-- Insert Games
INSERT INTO games (game_id, game_date, game_time_minutes, period1_length, period1_clock_type, period2_length, period2_clock_type, period3_length, period3_clock_type, opponent_name, our_score, their_score)
SELECT
    ID,
    Date || ' ' || Time,
    CASE WHEN LOWER(Tag) = 'tournament' THEN 75 ELSE 90 END,
    CASE WHEN LOWER(Tag) = 'tournament' THEN 780 ELSE 900 END, 'stop',
    CASE WHEN LOWER(Tag) = 'tournament' THEN 780 ELSE 900 END, 'stop',
    CASE WHEN LOWER(Tag) = 'tournament' THEN 780 ELSE 900 END, 'stop',
    NULLIF(Opponent, ''),
    COALESCE(NULLIF(For, ''), 0),
    COALESCE(NULLIF(Against, ''), 0)
FROM imp_games;

-- Insert Game Tags
INSERT INTO game_tag_mapping (game_id, tag_id)
SELECT g.ID, t.tag_id
FROM imp_games g
JOIN game_tags t ON LOWER(t.tag_name) = LOWER(g.Tag);

-- Pivot Game Roster
-- We create a massive union of all columns mapped to their specific jersey numbers
WITH raw_roster AS (
    SELECT ID as gid, 8 as jersey, g8 as code FROM imp_games
    UNION ALL SELECT ID, 31, g31 FROM imp_games
    UNION ALL SELECT ID, 6, d6 FROM imp_games
    UNION ALL SELECT ID, 19, d19 FROM imp_games
    UNION ALL SELECT ID, 47, d47 FROM imp_games
    UNION ALL SELECT ID, 81, d81 FROM imp_games
    UNION ALL SELECT ID, 88, d88 FROM imp_games
    UNION ALL SELECT ID, 89, d89 FROM imp_games
    UNION ALL SELECT ID, 7, f7 FROM imp_games
    UNION ALL SELECT ID, 16, f16 FROM imp_games
    UNION ALL SELECT ID, 18, f18 FROM imp_games
    UNION ALL SELECT ID, 22, f22 FROM imp_games
    UNION ALL SELECT ID, 24, f24 FROM imp_games
    UNION ALL SELECT ID, 30, f30 FROM imp_games
    UNION ALL SELECT ID, 34, f34 FROM imp_games
    UNION ALL SELECT ID, 86, f86 FROM imp_games
    UNION ALL SELECT ID, 90, f90 FROM imp_games
    UNION ALL SELECT ID, 97, f97 FROM imp_games
)
INSERT INTO game_roster (game_id, player_id, position, code)
SELECT
    rr.gid,
    r.player_id,
    CASE 
        -- Goalies
        WHEN rr.code IN ('S', 'b', 'R') THEN 'goalie'
        -- Defense
        WHEN rr.code IN ('D1', 'D2', 'D3') THEN 'defense'
        -- Forwards / Centers
        WHEN rr.code IN ('F1', 'F2', 'F3', 'F4') THEN 'forward'
        WHEN rr.code IN ('C1', 'C2', 'C3') THEN 'center'
        -- Scratches (e, u, -, empty) are mapped to 'scratch' by default logic or excluded?
        -- Original script treats 'e', 'u', '-', '' as 'scratch'.
        ELSE 'scratch'
    END as position,
    CASE
        WHEN rr.code IN ('S') THEN 's'
        WHEN rr.code IN ('b') THEN 'b'
        WHEN rr.code IN ('R') THEN 'r'
        WHEN rr.code IN ('D1', 'F1', 'C1') THEN '1'
        WHEN rr.code IN ('D2', 'F2', 'C2') THEN '2'
        WHEN rr.code IN ('D3', 'F3', 'C3') THEN '3'
        WHEN rr.code IN ('F4') THEN '4'
        WHEN rr.code IN ('e') THEN 'e'
        WHEN rr.code IN ('u') THEN 'u'
        ELSE 'e'
    END as normalized_code
FROM raw_roster rr
JOIN roster r ON r.jersey_number = rr.jersey
WHERE rr.code IS NOT NULL AND rr.code != '' AND rr.code != '-';

-- C. Goals For
-- ------------------------
CREATE TEMP TABLE imp_goals (Game, Tag, Goal, Assist, Assist2, OnIce, OnIce2, OnIce3, OnIce4);
.import "$clean_goals_for" imp_goals
DELETE FROM imp_goals WHERE Game = 'Game';

INSERT INTO goals_for (game_id, period, time_seconds, scorer_id, assist1_id, assist2_id, extra_skater1_id, extra_skater2_id, extra_skater3_id, extra_skater4_id, goal_type)
SELECT
    g.Game, 4, 0,
    r_goal.player_id,
    r_a1.player_id, r_a2.player_id,
    r_i1.player_id, r_i2.player_id, r_i3.player_id, r_i4.player_id,
    CASE 
        WHEN UPPER(g.Tag) IN ('PK', 'SH') THEN 'shorthanded'
        WHEN UPPER(g.Tag) = 'PP' THEN 'power_play'
        ELSE 'even_strength'
    END
FROM imp_goals g
JOIN roster r_goal ON r_goal.jersey_number = CAST(g.Goal AS INTEGER)
LEFT JOIN roster r_a1 ON r_a1.jersey_number = CAST(g.Assist AS INTEGER) AND g.Assist != '-'
LEFT JOIN roster r_a2 ON r_a2.jersey_number = CAST(g.Assist2 AS INTEGER) AND g.Assist2 != '-'
LEFT JOIN roster r_i1 ON r_i1.jersey_number = CAST(g.OnIce AS INTEGER) AND g.OnIce != '-'
LEFT JOIN roster r_i2 ON r_i2.jersey_number = CAST(g.OnIce2 AS INTEGER) AND g.OnIce2 != '-'
LEFT JOIN roster r_i3 ON r_i3.jersey_number = CAST(g.OnIce3 AS INTEGER) AND g.OnIce3 != '-'
LEFT JOIN roster r_i4 ON r_i4.jersey_number = CAST(g.OnIce4 AS INTEGER) AND g.OnIce4 != '-';

-- D. Goals Against
-- ------------------------
CREATE TEMP TABLE imp_ga (Game, Tag, I1, I2, I3, I4, I5, I6, Notes);
.import "$clean_goals_against" imp_ga
DELETE FROM imp_ga WHERE Game = 'Game';

INSERT INTO goals_against (game_id, period, time_seconds, on_ice1_id, on_ice2_id, on_ice3_id, on_ice4_id, on_ice5_id, on_ice6_id, goal_type)
SELECT
    g.Game, 4, 0,
    r1.player_id, r2.player_id, r3.player_id, r4.player_id, r5.player_id, r6.player_id,
    CASE 
        WHEN UPPER(g.Tag) IN ('PK', 'SH') THEN 'power_play'
        WHEN UPPER(g.Tag) = 'PP' THEN 'shorthanded'
        ELSE 'even_strength'
    END
FROM imp_ga g
LEFT JOIN roster r1 ON r1.jersey_number = CAST(g.I1 AS INTEGER) AND g.I1 NOT IN ('-', '?')
LEFT JOIN roster r2 ON r2.jersey_number = CAST(g.I2 AS INTEGER) AND g.I2 NOT IN ('-', '?')
LEFT JOIN roster r3 ON r3.jersey_number = CAST(g.I3 AS INTEGER) AND g.I3 NOT IN ('-', '?')
LEFT JOIN roster r4 ON r4.jersey_number = CAST(g.I4 AS INTEGER) AND g.I4 NOT IN ('-', '?')
LEFT JOIN roster r5 ON r5.jersey_number = CAST(g.I5 AS INTEGER) AND g.I5 NOT IN ('-', '?')
LEFT JOIN roster r6 ON r6.jersey_number = CAST(g.I6 AS INTEGER) AND g.I6 NOT IN ('-', '?')
WHERE g.I1 != '?' AND g.I2 != '?'; -- Filter unknowns

-- E. Penalties
-- ------------------------
CREATE TEMP TABLE imp_pen (Game, Player, Infraction, Time, Notes);
.import "$clean_penalties" imp_pen
DELETE FROM imp_pen WHERE Game = 'Game';

INSERT INTO penalties (game_id, period, time_seconds, player_id, penalty_type_id, notes)
SELECT
    p.Game, 4, 0,
    r.player_id,
    pt.penalty_type_id,
    NULLIF(p.Notes, '')
FROM imp_pen p
LEFT JOIN roster r ON r.jersey_number = CAST(p.Player AS INTEGER) AND p.Player != 'Bench'
JOIN penalty_types pt ON 
    (pt.penalty_length = CAST(p.Time AS INTEGER)) AND
    (
        LOWER(pt.penalty_name) = CASE 
            WHEN LOWER(TRIM(p.Infraction)) = 'high sticking' THEN 'high-sticking'
            WHEN LOWER(TRIM(p.Infraction)) = 'head contact' THEN 'head-contact'
            WHEN LOWER(TRIM(p.Infraction)) IN ('body checking', 'body contact') THEN 'body-checking'
            WHEN LOWER(TRIM(p.Infraction)) = 'check from behind' THEN 'check_from_behind'
            WHEN LOWER(TRIM(p.Infraction)) = 'cross checking' THEN 'cross-checking'
            WHEN LOWER(TRIM(p.Infraction)) = 'too many men' THEN 'too-many-men'
            WHEN TRIM(p.Infraction) = '?' THEN 'unknown'
            ELSE LOWER(TRIM(p.Infraction))
        END
    );

PRAGMA foreign_keys = ON;

SELECT 'Ingestion Complete' as Status;
SELECT COUNT(*) || ' Players Loaded' FROM roster;
SELECT COUNT(*) || ' Games Loaded' FROM games;
SELECT COUNT(*) || ' Goals For Loaded' FROM goals_for;
SELECT COUNT(*) || ' Penalties Loaded' FROM penalties;

EOF

echo "Done."