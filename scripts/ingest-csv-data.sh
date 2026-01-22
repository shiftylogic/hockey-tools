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
clean_passing_std="./.tmp_ingest/passing_std.csv"
clean_passing_tourn="./.tmp_ingest/passing_tourn.csv"
clean_practices="./.tmp_ingest/practices.csv"
clean_dryland="./.tmp_ingest/dryland.csv"
clean_drills1="./.tmp_ingest/drills1.csv"
clean_drills2="./.tmp_ingest/drills2.csv"

tr -d '\r' < "$DATA_DIR/roster.csv" > "$clean_roster"
tr -d '\r' < "$DATA_DIR/Games-Games.csv" > "$clean_games"
tr -d '\r' < "$DATA_DIR/Goals For-For.csv" > "$clean_goals_for"
tr -d '\r' < "$DATA_DIR/Goals Against-Against.csv" > "$clean_goals_against"
tr -d '\r' < "$DATA_DIR/Penalties-Table 1.csv" > "$clean_penalties"
tr -d '\r' < "$DATA_DIR/Practices-Practices.csv" > "$clean_practices"
tr -d '\r' < "$DATA_DIR/Practices-Dryland   Classroom.csv" > "$clean_dryland"
tr -d '\r' < "$DATA_DIR/Practices-Drill Selection (Practices 1 - 44).csv" > "$clean_drills1"
tr -d '\r' < "$DATA_DIR/Practices-Drill Selection (Practice 45 - ?).csv" > "$clean_drills2"

# Concatenate standard passing files with forced newlines to prevent merging last/first lines
{
    cat "$DATA_DIR/Passing-Exhibition.csv"
    echo ""
    cat "$DATA_DIR/Passing-League.csv"
    echo ""
    cat "$DATA_DIR/Passing-Tiering.csv"
} | tr -d '\r' > "$clean_passing_std"

tr -d '\r' < "$DATA_DIR/Passing-Tournaments.csv" > "$clean_passing_tourn"

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
DROP TABLE IF EXISTS team_passing_stats;
DROP TABLE IF EXISTS shots;
DROP TABLE IF EXISTS penalties;
DROP TABLE IF EXISTS goals_against;
DROP TABLE IF EXISTS goals_for;
DROP TABLE IF EXISTS game_tag_mapping;
DROP TABLE IF EXISTS game_tags;
DROP TABLE IF EXISTS game_roster;
DROP TABLE IF EXISTS absences;
DROP TABLE IF EXISTS attendance;
DROP TABLE IF EXISTS practice_drills;
DROP TABLE IF EXISTS drills;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS roster;
DROP TABLE IF EXISTS penalty_types;
DROP TABLE IF EXISTS games;

CREATE TABLE events (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL CHECK (event_type IN ('practice', 'dryland', 'classroom')),
    event_date TEXT NOT NULL
);

CREATE TABLE drills (
    drill_id INTEGER PRIMARY KEY AUTOINCREMENT,
    drill_name TEXT NOT NULL UNIQUE,
    drill_link TEXT
);

CREATE TABLE practice_drills (
    event_id INTEGER NOT NULL REFERENCES events(event_id),
    drill_id INTEGER NOT NULL REFERENCES drills(drill_id),
    PRIMARY KEY (event_id, drill_id)
);

CREATE TABLE attendance (
    event_id INTEGER NOT NULL REFERENCES events(event_id),
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    color TEXT CHECK (color IN ('blue', 'white')), -- Null for dryland/classroom
    PRIMARY KEY (event_id, player_id)
);

CREATE TABLE absences (
    event_id INTEGER NOT NULL REFERENCES events(event_id),
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    absence_type TEXT NOT NULL CHECK (absence_type IN ('excused', 'unexcused', 'injured')),
    note TEXT,
    PRIMARY KEY (event_id, player_id)
);

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

CREATE TABLE team_passing_stats (
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    attempts INTEGER NOT NULL,
    completed INTEGER NOT NULL,
    PRIMARY KEY (game_id, period)
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

-- F. Team Passing Stats
-- ------------------------
-- Standard (Exhibition, League, Tiering)
CREATE TEMP TABLE imp_pass_std (Game, Att, Comp, Pct, X, P1A, P1C, P1P, P2A, P2C, P2P, P3A, P3C, P3P);
.import "$clean_passing_std" imp_pass_std
DELETE FROM imp_pass_std WHERE Game = 'Game' OR Game IS NULL OR Game = '';

INSERT INTO team_passing_stats (game_id, period, attempts, completed)
SELECT Game, 1, P1A, P1C FROM imp_pass_std WHERE P1A IS NOT NULL AND P1A != ''
UNION ALL
SELECT Game, 2, P2A, P2C FROM imp_pass_std WHERE P2A IS NOT NULL AND P2A != ''
UNION ALL
SELECT Game, 3, P3A, P3C FROM imp_pass_std WHERE P3A IS NOT NULL AND P3A != '';

-- Tournament (Has OT columns)
CREATE TEMP TABLE imp_pass_tourn (Game, Att, Comp, Pct, X, P1A, P1C, P1P, P2A, P2C, P2P, P3A, P3C, P3P, OTA, OTC, OTP);
.import "$clean_passing_tourn" imp_pass_tourn
DELETE FROM imp_pass_tourn WHERE Game = 'Game';

INSERT INTO team_passing_stats (game_id, period, attempts, completed)
SELECT Game, 1, P1A, P1C FROM imp_pass_tourn WHERE P1A IS NOT NULL AND P1A != ''
UNION ALL
SELECT Game, 2, P2A, P2C FROM imp_pass_tourn WHERE P2A IS NOT NULL AND P2A != ''
UNION ALL
SELECT Game, 3, P3A, P3C FROM imp_pass_tourn WHERE P3A IS NOT NULL AND P3A != ''
UNION ALL
SELECT Game, 4, OTA, OTC FROM imp_pass_tourn WHERE OTA IS NOT NULL AND OTA != '-' AND OTA != '';

-- G. Practices & Attendance
-- ------------------------
-- 1. On-Ice Practices
-- Columns: No, Date, g8, g31, x3, d6, d19, d47, d81, d88, d89, x4, f7, f16, f18, f22, f24, f30, f34, f86, f90, f97
CREATE TEMP TABLE imp_practices (No, Date, g8, g31, x3, d6, d19, d47, d81, d88, d89, x4, f7, f16, f18, f22, f24, f30, f34, f86, f90, f97);
.import "$clean_practices" imp_practices
DELETE FROM imp_practices WHERE Date = 'Date' OR Date IS NULL OR Date = '';

-- Remove Cancelled Practices (All players are '-' or empty)
DELETE FROM imp_practices WHERE
  (g8  IS NULL OR g8  IN ('','-')) AND (g31 IS NULL OR g31 IN ('','-')) AND
  (d6  IS NULL OR d6  IN ('','-')) AND (d19 IS NULL OR d19 IN ('','-')) AND
  (d47 IS NULL OR d47 IN ('','-')) AND (d81 IS NULL OR d81 IN ('','-')) AND
  (d88 IS NULL OR d88 IN ('','-')) AND (d89 IS NULL OR d89 IN ('','-')) AND
  (f7  IS NULL OR f7  IN ('','-')) AND (f16 IS NULL OR f16 IN ('','-')) AND
  (f18 IS NULL OR f18 IN ('','-')) AND (f22 IS NULL OR f22 IN ('','-')) AND
  (f24 IS NULL OR f24 IN ('','-')) AND (f30 IS NULL OR f30 IN ('','-')) AND
  (f34 IS NULL OR f34 IN ('','-')) AND (f86 IS NULL OR f86 IN ('','-')) AND
  (f90 IS NULL OR f90 IN ('','-')) AND (f97 IS NULL OR f97 IN ('','-'));

-- Insert Events (Practices)
INSERT INTO events (event_type, event_date)
SELECT 'practice', Date FROM imp_practices;

-- Unpivot & Insert Attendance/Absences
WITH prac_raw AS (
    SELECT Date, 8 as jersey, g8 as code FROM imp_practices
    UNION ALL SELECT Date, 31, g31 FROM imp_practices
    UNION ALL SELECT Date, 6, d6 FROM imp_practices
    UNION ALL SELECT Date, 19, d19 FROM imp_practices
    UNION ALL SELECT Date, 47, d47 FROM imp_practices
    UNION ALL SELECT Date, 81, d81 FROM imp_practices
    UNION ALL SELECT Date, 88, d88 FROM imp_practices
    UNION ALL SELECT Date, 89, d89 FROM imp_practices
    UNION ALL SELECT Date, 7, f7 FROM imp_practices
    UNION ALL SELECT Date, 16, f16 FROM imp_practices
    UNION ALL SELECT Date, 18, f18 FROM imp_practices
    UNION ALL SELECT Date, 22, f22 FROM imp_practices
    UNION ALL SELECT Date, 24, f24 FROM imp_practices
    UNION ALL SELECT Date, 30, f30 FROM imp_practices
    UNION ALL SELECT Date, 34, f34 FROM imp_practices
    UNION ALL SELECT Date, 86, f86 FROM imp_practices
    UNION ALL SELECT Date, 90, f90 FROM imp_practices
    UNION ALL SELECT Date, 97, f97 FROM imp_practices
)
INSERT INTO attendance (event_id, player_id, color)
SELECT 
    e.event_id,
    r.player_id,
    CASE WHEN pr.code = 'B' THEN 'blue' ELSE 'white' END
FROM prac_raw pr
JOIN roster r ON r.jersey_number = pr.jersey
JOIN events e ON e.event_date = pr.Date AND e.event_type = 'practice'
WHERE pr.code IN ('B', 'W');

WITH prac_raw AS (
    SELECT Date, 8 as jersey, g8 as code FROM imp_practices
    UNION ALL SELECT Date, 31, g31 FROM imp_practices
    UNION ALL SELECT Date, 6, d6 FROM imp_practices
    UNION ALL SELECT Date, 19, d19 FROM imp_practices
    UNION ALL SELECT Date, 47, d47 FROM imp_practices
    UNION ALL SELECT Date, 81, d81 FROM imp_practices
    UNION ALL SELECT Date, 88, d88 FROM imp_practices
    UNION ALL SELECT Date, 89, d89 FROM imp_practices
    UNION ALL SELECT Date, 7, f7 FROM imp_practices
    UNION ALL SELECT Date, 16, f16 FROM imp_practices
    UNION ALL SELECT Date, 18, f18 FROM imp_practices
    UNION ALL SELECT Date, 22, f22 FROM imp_practices
    UNION ALL SELECT Date, 24, f24 FROM imp_practices
    UNION ALL SELECT Date, 30, f30 FROM imp_practices
    UNION ALL SELECT Date, 34, f34 FROM imp_practices
    UNION ALL SELECT Date, 86, f86 FROM imp_practices
    UNION ALL SELECT Date, 90, f90 FROM imp_practices
    UNION ALL SELECT Date, 97, f97 FROM imp_practices
)
INSERT INTO absences (event_id, player_id, absence_type)
SELECT 
    e.event_id,
    r.player_id,
    CASE 
        WHEN pr.code = 'u' THEN 'unexcused'
        WHEN pr.code = 'ij' THEN 'injured'
        ELSE 'excused'
    END
FROM prac_raw pr
JOIN roster r ON r.jersey_number = pr.jersey
JOIN events e ON e.event_date = pr.Date AND e.event_type = 'practice'
WHERE pr.code NOT IN ('B', 'W');


-- 2. Dryland / Classroom
-- Columns: Date, Type, d6, f7, g8, f16, f18, d19, f22, f24, f30, g31, f34, d47, d81, f86, d88, d89, f90, f97
CREATE TEMP TABLE imp_dryland (Date, Type, d6, f7, g8, f16, f18, d19, f22, f24, f30, g31, f34, d47, d81, f86, d88, d89, f90, f97);
.import "$clean_dryland" imp_dryland
DELETE FROM imp_dryland WHERE Date = 'Date' OR Date IS NULL OR Date = '';

-- Remove Cancelled Dryland/Classroom (All players are '-' or empty)
DELETE FROM imp_dryland WHERE
  (d6  IS NULL OR d6  IN ('','-')) AND (f7  IS NULL OR f7  IN ('','-')) AND
  (g8  IS NULL OR g8  IN ('','-')) AND (f16 IS NULL OR f16 IN ('','-')) AND
  (f18 IS NULL OR f18 IN ('','-')) AND (d19 IS NULL OR d19 IN ('','-')) AND
  (f22 IS NULL OR f22 IN ('','-')) AND (f24 IS NULL OR f24 IN ('','-')) AND
  (f30 IS NULL OR f30 IN ('','-')) AND (g31 IS NULL OR g31 IN ('','-')) AND
  (f34 IS NULL OR f34 IN ('','-')) AND (d47 IS NULL OR d47 IN ('','-')) AND
  (d81 IS NULL OR d81 IN ('','-')) AND (f86 IS NULL OR f86 IN ('','-')) AND
  (d88 IS NULL OR d88 IN ('','-')) AND (d89 IS NULL OR d89 IN ('','-')) AND
  (f90 IS NULL OR f90 IN ('','-')) AND (f97 IS NULL OR f97 IN ('','-'));

-- Insert Events
INSERT INTO events (event_type, event_date)
SELECT 
    CASE WHEN Type = 'C' THEN 'classroom' ELSE 'dryland' END,
    Date
FROM imp_dryland;

-- Unpivot & Insert
WITH dry_raw AS (
    SELECT Date, Type, 6 as jersey, d6 as code FROM imp_dryland
    UNION ALL SELECT Date, Type, 7, f7 FROM imp_dryland
    UNION ALL SELECT Date, Type, 8, g8 FROM imp_dryland
    UNION ALL SELECT Date, Type, 16, f16 FROM imp_dryland
    UNION ALL SELECT Date, Type, 18, f18 FROM imp_dryland
    UNION ALL SELECT Date, Type, 19, d19 FROM imp_dryland
    UNION ALL SELECT Date, Type, 22, f22 FROM imp_dryland
    UNION ALL SELECT Date, Type, 24, f24 FROM imp_dryland
    UNION ALL SELECT Date, Type, 30, f30 FROM imp_dryland
    UNION ALL SELECT Date, Type, 31, g31 FROM imp_dryland
    UNION ALL SELECT Date, Type, 34, f34 FROM imp_dryland
    UNION ALL SELECT Date, Type, 47, d47 FROM imp_dryland
    UNION ALL SELECT Date, Type, 81, d81 FROM imp_dryland
    UNION ALL SELECT Date, Type, 86, f86 FROM imp_dryland
    UNION ALL SELECT Date, Type, 88, d88 FROM imp_dryland
    UNION ALL SELECT Date, Type, 89, d89 FROM imp_dryland
    UNION ALL SELECT Date, Type, 90, f90 FROM imp_dryland
    UNION ALL SELECT Date, Type, 97, f97 FROM imp_dryland
)
INSERT INTO attendance (event_id, player_id, color)
SELECT 
    e.event_id,
    r.player_id,
    NULL
FROM dry_raw dr
JOIN roster r ON r.jersey_number = dr.jersey
JOIN events e ON e.event_date = dr.Date AND e.event_type = (CASE WHEN dr.Type = 'C' THEN 'classroom' ELSE 'dryland' END)
WHERE dr.code = '+';

WITH dry_raw AS (
    SELECT Date, Type, 6 as jersey, d6 as code FROM imp_dryland
    UNION ALL SELECT Date, Type, 7, f7 FROM imp_dryland
    UNION ALL SELECT Date, Type, 8, g8 FROM imp_dryland
    UNION ALL SELECT Date, Type, 16, f16 FROM imp_dryland
    UNION ALL SELECT Date, Type, 18, f18 FROM imp_dryland
    UNION ALL SELECT Date, Type, 19, d19 FROM imp_dryland
    UNION ALL SELECT Date, Type, 22, f22 FROM imp_dryland
    UNION ALL SELECT Date, Type, 24, f24 FROM imp_dryland
    UNION ALL SELECT Date, Type, 30, f30 FROM imp_dryland
    UNION ALL SELECT Date, Type, 31, g31 FROM imp_dryland
    UNION ALL SELECT Date, Type, 34, f34 FROM imp_dryland
    UNION ALL SELECT Date, Type, 47, d47 FROM imp_dryland
    UNION ALL SELECT Date, Type, 81, d81 FROM imp_dryland
    UNION ALL SELECT Date, Type, 86, f86 FROM imp_dryland
    UNION ALL SELECT Date, Type, 88, d88 FROM imp_dryland
    UNION ALL SELECT Date, Type, 89, d89 FROM imp_dryland
    UNION ALL SELECT Date, Type, 90, f90 FROM imp_dryland
    UNION ALL SELECT Date, Type, 97, f97 FROM imp_dryland
)
INSERT INTO absences (event_id, player_id, absence_type)
SELECT 
    e.event_id,
    r.player_id,
    CASE 
        WHEN dr.code = 'u' THEN 'unexcused'
        WHEN dr.code = 'ij' THEN 'injured'
        ELSE 'excused'
    END
FROM dry_raw dr
JOIN roster r ON r.jersey_number = dr.jersey
JOIN events e ON e.event_date = dr.Date AND e.event_type = (CASE WHEN dr.Type = 'C' THEN 'classroom' ELSE 'dryland' END)
WHERE dr.code != '+' AND dr.code IS NOT NULL AND dr.code != '';


-- H. Drills & Practice Mapping
-- ------------------------
-- 1. Ingest Unique Drills
CREATE TEMP TABLE imp_drill_names (name);
-- Extract names from both files, skipping first 2 rows
.mode csv
.import "|tail -n +3 '$clean_drills1' | cut -d, -f1" imp_drill_names
.import "|tail -n +3 '$clean_drills2' | cut -d, -f1" imp_drill_names

INSERT OR IGNORE INTO drills (drill_name)
SELECT DISTINCT name FROM imp_drill_names WHERE name IS NOT NULL AND name != '';

-- 2. Map Drills to Practices (Unpivot)
-- We'll use a temporary mapping table and unpivot the wide CSVs.
-- This is done by creating a temp table for each file and using a CTE to unpivot.

-- File 1: Practices 1-44
CREATE TEMP TABLE imp_drills_1 (Name, Cat, 
    p1, p2, p3, p4, p5, p6, p7, p8, p9, p10,
    p11, p12, p13, p14, p15, p16, p17, p18, p19, p20,
    p21, p22, p23, p24, p25, p26, p27, p28, p29, p30,
    p31, p32, p33, p34, p35, p36, p37, p38, p39, p40,
    p41, p42, p43, p44);
.import "$clean_drills1" imp_drills_1
DELETE FROM imp_drills_1 WHERE Name IS NULL OR Name = '' OR p1 = '1'; -- Header rows

INSERT INTO practice_drills (event_id, drill_id)
SELECT e.event_id, d.drill_id
FROM (
    SELECT Name, 1 as pid, p1 as val FROM imp_drills_1 UNION ALL
    SELECT Name, 2, p2 FROM imp_drills_1 UNION ALL
    SELECT Name, 3, p3 FROM imp_drills_1 UNION ALL
    SELECT Name, 4, p4 FROM imp_drills_1 UNION ALL
    SELECT Name, 5, p5 FROM imp_drills_1 UNION ALL
    SELECT Name, 6, p6 FROM imp_drills_1 UNION ALL
    SELECT Name, 7, p7 FROM imp_drills_1 UNION ALL
    SELECT Name, 8, p8 FROM imp_drills_1 UNION ALL
    SELECT Name, 9, p9 FROM imp_drills_1 UNION ALL
    SELECT Name, 10, p10 FROM imp_drills_1 UNION ALL
    SELECT Name, 11, p11 FROM imp_drills_1 UNION ALL
    SELECT Name, 12, p12 FROM imp_drills_1 UNION ALL
    SELECT Name, 13, p13 FROM imp_drills_1 UNION ALL
    SELECT Name, 14, p14 FROM imp_drills_1 UNION ALL
    SELECT Name, 15, p15 FROM imp_drills_1 UNION ALL
    SELECT Name, 16, p16 FROM imp_drills_1 UNION ALL
    SELECT Name, 17, p17 FROM imp_drills_1 UNION ALL
    SELECT Name, 18, p18 FROM imp_drills_1 UNION ALL
    SELECT Name, 19, p19 FROM imp_drills_1 UNION ALL
    SELECT Name, 20, p20 FROM imp_drills_1 UNION ALL
    SELECT Name, 21, p21 FROM imp_drills_1 UNION ALL
    SELECT Name, 22, p22 FROM imp_drills_1 UNION ALL
    SELECT Name, 23, p23 FROM imp_drills_1 UNION ALL
    SELECT Name, 24, p24 FROM imp_drills_1 UNION ALL
    SELECT Name, 25, p25 FROM imp_drills_1 UNION ALL
    SELECT Name, 26, p26 FROM imp_drills_1 UNION ALL
    SELECT Name, 27, p27 FROM imp_drills_1 UNION ALL
    SELECT Name, 28, p28 FROM imp_drills_1 UNION ALL
    SELECT Name, 29, p29 FROM imp_drills_1 UNION ALL
    SELECT Name, 30, p30 FROM imp_drills_1 UNION ALL
    SELECT Name, 31, p31 FROM imp_drills_1 UNION ALL
    SELECT Name, 32, p32 FROM imp_drills_1 UNION ALL
    SELECT Name, 33, p33 FROM imp_drills_1 UNION ALL
    SELECT Name, 34, p34 FROM imp_drills_1 UNION ALL
    SELECT Name, 35, p35 FROM imp_drills_1 UNION ALL
    SELECT Name, 36, p36 FROM imp_drills_1 UNION ALL
    SELECT Name, 37, p37 FROM imp_drills_1 UNION ALL
    SELECT Name, 38, p38 FROM imp_drills_1 UNION ALL
    SELECT Name, 39, p39 FROM imp_drills_1 UNION ALL
    SELECT Name, 40, p40 FROM imp_drills_1 UNION ALL
    SELECT Name, 41, p41 FROM imp_drills_1 UNION ALL
    SELECT Name, 42, p42 FROM imp_drills_1 UNION ALL
    SELECT Name, 43, p43 FROM imp_drills_1 UNION ALL
    SELECT Name, 44, p44 FROM imp_drills_1
) m
JOIN drills d ON d.drill_name = m.Name
JOIN imp_practices ip ON CAST(ip.No AS INTEGER) = m.pid
JOIN events e ON e.event_date = ip.Date AND e.event_type = 'practice'
WHERE m.val = 'TRUE';

-- File 2: Practices 45-87
CREATE TEMP TABLE imp_drills_2 (Name, Cat, X,
    p45, p46, p47, p48, p49, p50, p51, p52, p53, p54, p55, p56, p57, p58, p59, p60,
    p61, p62, p63, p64, p65, p66, p67, p68, p69, p70, p71, p72, p73, p74, p75, p76, p77, p78, p79, p80,
    p81, p82, p83, p84, p85, p86, p87);
.import "$clean_drills2" imp_drills_2
DELETE FROM imp_drills_2 WHERE Name IS NULL OR Name = '' OR p45 = '45';

INSERT INTO practice_drills (event_id, drill_id)
SELECT e.event_id, d.drill_id
FROM (
    SELECT Name, 45 as pid, p45 as val FROM imp_drills_2 UNION ALL
    SELECT Name, 46, p46 FROM imp_drills_2 UNION ALL
    SELECT Name, 47, p47 FROM imp_drills_2 UNION ALL
    SELECT Name, 48, p48 FROM imp_drills_2 UNION ALL
    SELECT Name, 49, p49 FROM imp_drills_2 UNION ALL
    SELECT Name, 50, p50 FROM imp_drills_2 UNION ALL
    SELECT Name, 51, p51 FROM imp_drills_2 UNION ALL
    SELECT Name, 52, p52 FROM imp_drills_2 UNION ALL
    SELECT Name, 53, p53 FROM imp_drills_2 UNION ALL
    SELECT Name, 54, p54 FROM imp_drills_2 UNION ALL
    SELECT Name, 55, p55 FROM imp_drills_2 UNION ALL
    SELECT Name, 56, p56 FROM imp_drills_2 UNION ALL
    SELECT Name, 57, p57 FROM imp_drills_2 UNION ALL
    SELECT Name, 58, p58 FROM imp_drills_2 UNION ALL
    SELECT Name, 59, p59 FROM imp_drills_2 UNION ALL
    SELECT Name, 60, p60 FROM imp_drills_2 UNION ALL
    SELECT Name, 61, p61 FROM imp_drills_2 UNION ALL
    SELECT Name, 62, p62 FROM imp_drills_2 UNION ALL
    SELECT Name, 63, p63 FROM imp_drills_2 UNION ALL
    SELECT Name, 64, p64 FROM imp_drills_2 UNION ALL
    SELECT Name, 65, p65 FROM imp_drills_2 UNION ALL
    SELECT Name, 66, p66 FROM imp_drills_2 UNION ALL
    SELECT Name, 67, p67 FROM imp_drills_2 UNION ALL
    SELECT Name, 68, p68 FROM imp_drills_2 UNION ALL
    SELECT Name, 69, p69 FROM imp_drills_2 UNION ALL
    SELECT Name, 70, p70 FROM imp_drills_2 UNION ALL
    SELECT Name, 71, p71 FROM imp_drills_2 UNION ALL
    SELECT Name, 72, p72 FROM imp_drills_2 UNION ALL
    SELECT Name, 73, p73 FROM imp_drills_2 UNION ALL
    SELECT Name, 74, p74 FROM imp_drills_2 UNION ALL
    SELECT Name, 75, p75 FROM imp_drills_2 UNION ALL
    SELECT Name, 76, p76 FROM imp_drills_2 UNION ALL
    SELECT Name, 77, p77 FROM imp_drills_2 UNION ALL
    SELECT Name, 78, p78 FROM imp_drills_2 UNION ALL
    SELECT Name, 79, p79 FROM imp_drills_2 UNION ALL
    SELECT Name, 80, p80 FROM imp_drills_2 UNION ALL
    SELECT Name, 81, p81 FROM imp_drills_2 UNION ALL
    SELECT Name, 82, p82 FROM imp_drills_2 UNION ALL
    SELECT Name, 83, p83 FROM imp_drills_2 UNION ALL
    SELECT Name, 84, p84 FROM imp_drills_2 UNION ALL
    SELECT Name, 85, p85 FROM imp_drills_2 UNION ALL
    SELECT Name, 86, p86 FROM imp_drills_2 UNION ALL
    SELECT Name, 87, p87 FROM imp_drills_2
) m
JOIN drills d ON d.drill_name = m.Name
JOIN imp_practices ip ON CAST(ip.No AS INTEGER) = m.pid
JOIN events e ON e.event_date = ip.Date AND e.event_type = 'practice'
WHERE m.val = 'TRUE';


PRAGMA foreign_keys = ON;

SELECT 'Ingestion Complete' as Status;
SELECT COUNT(*) || ' Players Loaded' FROM roster;
SELECT COUNT(*) || ' Games Loaded' FROM games;
SELECT COUNT(*) || ' Goals For Loaded' FROM goals_for;
SELECT COUNT(*) || ' Penalties Loaded' FROM penalties;
SELECT COUNT(*) || ' Passing Stats Loaded' FROM team_passing_stats;
SELECT COUNT(*) || ' Practice Events Loaded' FROM events;
SELECT COUNT(*) || ' Attendance Records' FROM attendance;
SELECT COUNT(*) || ' Absence Records' FROM absences;
SELECT COUNT(*) || ' Unique Drills Loaded' FROM drills;
SELECT COUNT(*) || ' Practice-Drill Mappings' FROM practice_drills;

EOF

echo "Done."