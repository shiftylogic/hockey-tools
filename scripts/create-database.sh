#!/usr/bin/env bash
#
# Copyright (c) 2025-present Robert Anderson.
# SPDX-License-Identifier: MIT
#
# create-database.sh - Creates the hockey stats SQLite database schema
#
# Usage: ./create-database.sh [database_file]
#   Default database file: stats.db
#
# Requires: sqlite3 CLI tool
#   Install on Ubuntu/Debian: sudo apt-get install sqlite3
#   Install on macOS: brew install sqlite3
#

set -e

DB_FILE="${1:-stats.db}"

# Check for sqlite3
if ! command -v sqlite3 &> /dev/null; then
    echo "Error: sqlite3 command not found."
    echo ""
    echo "To install sqlite3:"
    echo "  Ubuntu/Debian: sudo apt-get install sqlite3"
    echo "  macOS: brew install sqlite3"
    exit 1
fi

echo "Creating database: $DB_FILE"

sqlite3 "$DB_FILE" <<'EOF'
PRAGMA foreign_keys = ON;

-- ============================================================================
-- CORE TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS games (
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

CREATE TABLE IF NOT EXISTS game_tags (
    tag_id INTEGER PRIMARY KEY,
    tag_name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS game_tag_mapping (
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    tag_id INTEGER NOT NULL REFERENCES game_tags(tag_id),
    PRIMARY KEY (game_id, tag_id)
);

CREATE TABLE IF NOT EXISTS roster (
    player_id INTEGER PRIMARY KEY,
    jersey_number INTEGER NOT NULL UNIQUE,
    player_name TEXT NOT NULL,
    primary_position TEXT NOT NULL CHECK (primary_position IN ('Forward', 'Defense', 'Goalie')),
    secondary_positions TEXT,
    birth_year INTEGER NOT NULL,
    handedness TEXT NOT NULL CHECK (handedness IN ('left', 'right'))
);

CREATE TABLE IF NOT EXISTS penalty_types (
    penalty_type_id INTEGER PRIMARY KEY,
    penalty_name TEXT NOT NULL,
    penalty_category TEXT NOT NULL CHECK (penalty_category IN ('minor', 'major', 'misconduct', 'game_misconduct', 'match')),
    penalty_length INTEGER NOT NULL
);

-- ============================================================================
-- STAT TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS goals_for (
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

CREATE TABLE IF NOT EXISTS goals_against (
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

CREATE TABLE IF NOT EXISTS penalties (
    penalty_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    penalty_type_id INTEGER NOT NULL REFERENCES penalty_types(penalty_type_id),
    served_by_id INTEGER REFERENCES roster(player_id),
    notes TEXT(255)
);

CREATE TABLE IF NOT EXISTS shots (
    shot_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    result TEXT NOT NULL CHECK (result IN ('missed', 'saved', 'blocked', 'scored')),
    origin_zone INTEGER NOT NULL CHECK (origin_zone BETWEEN 1 AND 8)
);

CREATE TABLE IF NOT EXISTS passes (
    pass_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    target_player_id INTEGER NOT NULL REFERENCES roster(player_id),
    result TEXT NOT NULL CHECK (result IN ('good', 'off_target', 'missed', 'intercepted')),
    origin_zone TEXT NOT NULL CHECK (origin_zone IN ('defensive', 'offensive', 'neutral'))
);

CREATE TABLE IF NOT EXISTS blocks (
    block_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    origin_zone INTEGER NOT NULL CHECK (origin_zone BETWEEN 1 AND 8)
);

CREATE TABLE IF NOT EXISTS takeaways (
    takeaway_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    origin_zone TEXT NOT NULL CHECK (origin_zone IN ('defensive', 'offensive', 'neutral'))
);

CREATE TABLE IF NOT EXISTS giveaways (
    giveaway_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    origin_zone TEXT NOT NULL CHECK (origin_zone IN ('defensive', 'offensive', 'neutral'))
);

CREATE TABLE IF NOT EXISTS player_changes (
    change_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    incoming_id INTEGER NOT NULL REFERENCES roster(player_id),
    outgoing_id INTEGER NOT NULL REFERENCES roster(player_id)
);

CREATE TABLE IF NOT EXISTS saves (
    save_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    goalie_id INTEGER NOT NULL REFERENCES roster(player_id)
);

CREATE TABLE IF NOT EXISTS faceoffs (
    faceoff_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    time_seconds INTEGER NOT NULL,
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    win_loss TEXT NOT NULL CHECK (win_loss IN ('win', 'loss')),
    extra1_id INTEGER REFERENCES roster(player_id),
    extra2_id INTEGER REFERENCES roster(player_id),
    extra3_id INTEGER REFERENCES roster(player_id),
    extra4_id INTEGER REFERENCES roster(player_id),
    extra5_id INTEGER REFERENCES roster(player_id)
);

CREATE TABLE IF NOT EXISTS shifts (
    shift_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    player_id INTEGER NOT NULL REFERENCES roster(player_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    start_seconds INTEGER NOT NULL,
    end_seconds INTEGER NOT NULL
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Goals + Assists queries
CREATE INDEX IF NOT EXISTS idx_goals_for_scorer ON goals_for(scorer_id);
CREATE INDEX IF NOT EXISTS idx_goals_for_assist1 ON goals_for(assist1_id);
CREATE INDEX IF NOT EXISTS idx_goals_for_assist2 ON goals_for(assist2_id);
CREATE INDEX IF NOT EXISTS idx_goals_for_game ON goals_for(game_id);

-- Plus/Minus queries
CREATE INDEX IF NOT EXISTS idx_gf_extra_skater ON goals_for(extra_skater1_id, extra_skater2_id, extra_skater3_id, extra_skater4_id);
CREATE INDEX IF NOT EXISTS idx_ga_on_ice ON goals_against(on_ice1_id, on_ice2_id, on_ice3_id, on_ice4_id, on_ice5_id, on_ice6_id);
CREATE INDEX IF NOT EXISTS idx_goals_against_game ON goals_against(game_id);

-- Per-game stat queries
CREATE INDEX IF NOT EXISTS idx_shots_player_game ON shots(player_id, game_id);
CREATE INDEX IF NOT EXISTS idx_penalties_player_game ON penalties(player_id, game_id);
CREATE INDEX IF NOT EXISTS idx_faceoffs_player_game ON faceoffs(player_id, game_id);

-- General FK indexes
CREATE INDEX IF NOT EXISTS idx_games_date ON games(game_date);
CREATE INDEX IF NOT EXISTS idx_shots_game ON shots(game_id);
CREATE INDEX IF NOT EXISTS idx_passes_game ON passes(game_id);
CREATE INDEX IF NOT EXISTS idx_blocks_game ON blocks(game_id);
CREATE INDEX IF NOT EXISTS idx_takeaways_game ON takeaways(game_id);
CREATE INDEX IF NOT EXISTS idx_giveaways_game ON giveaways(game_id);
CREATE INDEX IF NOT EXISTS idx_player_changes_game ON player_changes(game_id);
CREATE INDEX IF NOT EXISTS idx_saves_game ON saves(game_id);
CREATE INDEX IF NOT EXISTS idx_penalties_game ON penalties(game_id);
CREATE INDEX IF NOT EXISTS idx_faceoffs_game ON faceoffs(game_id);

-- Penalty queries
CREATE INDEX IF NOT EXISTS idx_penalties_type_category ON penalty_types(penalty_category);
CREATE INDEX IF NOT EXISTS idx_penalties_player_type ON penalties(penalty_type_id);

-- Shift queries (ice time)
CREATE INDEX IF NOT EXISTS idx_shifts_player_game ON shifts(player_id, game_id);
CREATE INDEX IF NOT EXISTS idx_shifts_period ON shifts(player_id, game_id, period);

-- ============================================================================
-- SEED DATA
-- ============================================================================

INSERT OR IGNORE INTO game_tags (tag_name) VALUES
    ('PNAHA'),
    ('league'),
    ('tournament'),
    ('exhibition'),
    ('Canada'),
    ('tiering'),
    ('scrimmage');

INSERT OR IGNORE INTO penalty_types (penalty_name, penalty_category, penalty_length) VALUES
    ('slashing', 'minor', 2),
    ('slashing', 'major', 5),
    ('tripping', 'minor', 2),
    ('tripping', 'major', 5),
    ('hooking', 'minor', 2),
    ('hooking', 'major', 5),
    ('interference', 'minor', 2),
    ('interference', 'major', 5),
    ('holding', 'minor', 2),
    ('holding', 'major', 5),
    ('high_stick', 'minor', 2),
    ('high_stick', 'major', 5),
    ('cross_check', 'minor', 2),
    ('cross_check', 'major', 5),
    ('charging', 'minor', 2),
    ('charging', 'major', 5),
    ('roughing', 'minor', 2),
    ('roughing', 'major', 5),
    ('delay_of_game', 'minor', 2),
    ('too_many_men', 'minor', 2),
    ('bench_minor', 'minor', 2),
    ('checking_from_behind', 'major', 5),
    ('checking_to_head', 'major', 5),
    ('fighting', 'major', 5),
    ('butt_ending', 'major', 5),
    ('hair_pulling', 'major', 5),
    ('kicking', 'major', 5),
    ('kneeing', 'major', 5),
    ('spearing', 'major', 5),
    ('misconduct', 'misconduct', 10),
    ('game_misconduct', 'game_misconduct', 10),
    ('match', 'match', 5);

-- Verify setup
SELECT 'Database created successfully.' AS status;
SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';
EOF

echo "Database schema created: $DB_FILE"
