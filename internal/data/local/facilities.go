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
	kFetchFacilitiesQuery = `
		SELECT id, name FROM facilities
			WHERE id > ?
			ORDER BY id ASC
			LIMIT 100
	`

	kFetchFacilityQuery = `
		SELECT id, name FROM facilities
			WHERE id = ?
	`
)

type facility struct {
	id      int64
	name    string
	address string
	city    string
	state   string
}

func (f *facility) ID() data.EntityID { return data.EntityID(f.id) }
func (f *facility) Name() string      { return f.name }
func (f *facility) Address() string   { return f.address }
func (f *facility) City() string      { return f.city }
func (f *facility) State() string     { return f.state }

type facilities struct {
	db        *sql.DB
	fetchList *sql.Stmt
	fetchID   *sql.Stmt
}

func newFacilities(db *sql.DB) (*facilities, error) {
	if err := ensureFacilities(db); err != nil {
		return nil, err
	}

	fetchList, err := db.Prepare(kFetchFacilitiesQuery)
	if err != nil {
		return nil, err
	}

	fetchID, err := db.Prepare(kFetchFacilityQuery)
	if err != nil {
		return nil, err
	}

	return &facilities{
		db,
		fetchList,
		fetchID,
	}, nil
}

func (f *facilities) List(token int64) ([]data.Facility, int64, error) {
	rows, err := f.fetchList.Query(token)
	if err != nil {
		return nil, -1, err
	}

	data := []data.Facility{}
	for rows.Next() {
		f := &facility{}
		err = rows.Scan(&f.id, &f.name)
		if err != nil {
			return nil, token, err
		}

		token = f.id
		data = append(data, f)
	}

	return data, token, nil
}

func (f *facilities) ByID(id data.EntityID) (data.Facility, error) {
	ret := &facility{}

	err := f.fetchID.QueryRow(id).Scan(&ret.id, &ret.name)
	if err == nil {
		return ret, nil
	}

	if errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}

	return nil, data.ErrorUnknownFacilityID
}

/**
 *
 * Functions used for manipulating 'facilities' tables.
 *
 */

const (
	kFacilitiesTableCreate = `
		CREATE TABLE IF NOT EXISTS facilities (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL
		)
	`
)

func ensureFacilities(db *sql.DB) error {
	if _, err := db.Exec(kFacilitiesTableCreate); err != nil {
		return fmt.Errorf("[ensureFacilities] failed to create 'facilities' table - %w", err)
	}

	return nil
}
