// MIT License
//
// Copyright (c) 2024-present Robert Anderson
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package local

import (
	"database/sql"
	"errors"
	"fmt"

	"shiftylogic.dev/hockey-tools/internal/data"
)

const (
	kFetchPlayersQuery = `
		SELECT id, team, name, number FROM players
			WHERE id > ?
			ORDER BY id ASC
			LIMIT 100
	`

	kFetchPlayerQuery = `
		SELECT id, team, name, number FROM players
			WHERE id = ?
	`

	kFetchPlayersTeamQuery = `
		SELECT id, team, name, number FROM players
			WHERE team = ?
	`
)

type player struct {
	id     int64
	team   int64
	name   string
	number int
}

func (p *player) ID() data.EntityID   { return data.EntityID(p.id) }
func (p *player) Team() data.EntityID { return data.EntityID(p.team) }
func (p *player) Name() string        { return p.name }
func (p *player) Number() int         { return p.number }

type players struct {
	db        *sql.DB
	fetchList *sql.Stmt
	fetchID   *sql.Stmt
	fetchTeam *sql.Stmt
}

func newPlayers(db *sql.DB) (*players, error) {
	if err := ensurePlayers(db); err != nil {
		return nil, err
	}

	fetchList, err := db.Prepare(kFetchPlayersQuery)
	if err != nil {
		return nil, err
	}

	fetchID, err := db.Prepare(kFetchPlayerQuery)
	if err != nil {
		return nil, err
	}

	fetchTeam, err := db.Prepare(kFetchPlayersTeamQuery)
	if err != nil {
		return nil, err
	}

	return &players{
		db,
		fetchList,
		fetchID,
		fetchTeam,
	}, nil
}

func (p *players) List(token int64) ([]data.Player, int64, error) {
	rows, err := p.fetchList.Query(token)
	if err != nil {
		return nil, -1, err
	}

	data := []data.Player{}
	for rows.Next() {
		np := &player{}
		err = rows.Scan(&np.id, &np.team, &np.name, &np.number)
		if err != nil {
			return nil, token, err
		}

		token = np.id
		data = append(data, np)
	}

	return data, token, nil
}

func (p *players) ByID(id data.EntityID) (data.Player, error) {
	ret := &player{}

	err := p.fetchID.QueryRow(id).Scan(&ret.id, &ret.team, &ret.name, &ret.number)
	if err == nil {
		return ret, nil
	}

	if errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}

	return nil, data.ErrorUnknownPlayerID
}

func (p *players) ByTeam(team data.EntityID) ([]data.Player, error) {
	rows, err := p.fetchTeam.Query(team)
	if err != nil {
		return nil, err
	}

	data := []data.Player{}
	for rows.Next() {
		np := &player{}
		err = rows.Scan(&np.id, &np.team, &np.name, &np.number)
		if err != nil {
			return nil, err
		}

		data = append(data, np)
	}

	return data, nil

}

/**
 *
 * Functions used for manipulating 'staff' tables.
 *
 */

const (
	kPlayersTableCreate = `
		CREATE TABLE IF NOT EXISTS players (
			id INTEGER PRIMARY KEY,
			team INTEGER,
			name TEXT NOT NULL,
			number INT,
			UNIQUE(team, number)
		)
	`
)

func ensurePlayers(db *sql.DB) error {
	if _, err := db.Exec(kPlayersTableCreate); err != nil {
		return fmt.Errorf("[ensurePlayers] failed to create 'players' table - %w", err)
	}

	return nil
}
