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
	kFetchStaffQuery = `
		SELECT id, team, name, role FROM staff
			WHERE id > ?
			ORDER BY id ASC
			LIMIT 100
	`

	kFetchStaffMemberQuery = `
		SELECT id, team, name, role FROM staff
			WHERE id = ?
	`

	kFetchStaffTeamQuery = `
		SELECT id, team, name, role FROM staff
			WHERE team = ?
	`
)

type staffMember struct {
	id   int64
	team int64
	name string
	role string
}

func (sm *staffMember) ID() data.EntityID   { return data.EntityID(sm.id) }
func (sm *staffMember) Team() data.EntityID { return data.EntityID(sm.team) }
func (sm *staffMember) Name() string        { return sm.name }
func (sm *staffMember) Role() string        { return sm.name }

type staff struct {
	db        *sql.DB
	fetchList *sql.Stmt
	fetchID   *sql.Stmt
	fetchTeam *sql.Stmt
}

func newStaff(db *sql.DB) (*staff, error) {
	if err := ensureStaff(db); err != nil {
		return nil, err
	}

	fetchList, err := db.Prepare(kFetchStaffQuery)
	if err != nil {
		return nil, err
	}

	fetchID, err := db.Prepare(kFetchStaffMemberQuery)
	if err != nil {
		return nil, err
	}

	fetchTeam, err := db.Prepare(kFetchStaffTeamQuery)
	if err != nil {
		return nil, err
	}

	return &staff{
		db,
		fetchList,
		fetchID,
		fetchTeam,
	}, nil
}

func (s *staff) List(token int64) ([]data.StaffMember, int64, error) {
	rows, err := s.fetchList.Query(token)
	if err != nil {
		return nil, -1, err
	}

	data := []data.StaffMember{}
	for rows.Next() {
		sm := &staffMember{}
		err = rows.Scan(&sm.id, &sm.team, &sm.name, &sm.role)
		if err != nil {
			return nil, token, err
		}

		token = sm.id
		data = append(data, sm)
	}

	return data, token, nil
}

func (s *staff) ByID(id data.EntityID) (data.StaffMember, error) {
	ret := &staffMember{}

	err := s.fetchID.QueryRow(id).Scan(&ret.id, &ret.team, &ret.name, &ret.role)
	if err == nil {
		return ret, nil
	}

	if errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}

	return nil, data.ErrorUnknownStaffID
}

func (s *staff) ByTeam(team data.EntityID) ([]data.StaffMember, error) {
	rows, err := s.fetchTeam.Query(team)
	if err != nil {
		return nil, err
	}

	data := []data.StaffMember{}
	for rows.Next() {
		sm := &staffMember{}
		err = rows.Scan(&sm.id, &sm.team, &sm.name, &sm.role)
		if err != nil {
			return nil, err
		}

		data = append(data, sm)
	}

	return data, nil

}

/**
 *
 * Functions used for manipulating 'staff' tables.
 *
 */

const (
	kStaffTableCreate = `
		CREATE TABLE IF NOT EXISTS staff (
			id INTEGER PRIMARY KEY,
			team INTEGER,
			name TEXT NOT NULL,
			role TEXT NOT NULL
		)
	`
)

func ensureStaff(db *sql.DB) error {
	if _, err := db.Exec(kStaffTableCreate); err != nil {
		return fmt.Errorf("[ensureStaff] failed to create 'staff' table - %w", err)
	}

	return nil
}
