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

	_ "github.com/mattn/go-sqlite3"

	"shiftylogic.dev/hockey-tools/internal/data"
)

var (
	kErrorOpeningDatabase = errors.New("failed to open database file")
)

type localStore struct {
	db         *sql.DB
	facilities *facilities
	players    *players
	staff      *staff
}

func (store *localStore) Close()                      { store.db.Close() }
func (store *localStore) Facilities() data.Facilities { return store.facilities }
func (store *localStore) Players() data.Players       { return store.players }
func (store *localStore) Staff() data.Staff           { return store.staff }

func Open(dataFile string) (data.Store, error) {
	db, err := sql.Open("sqlite3", dataFile)
	if err != nil {
		return nil, fmt.Errorf("[local.Open] failed to open database file - %w", err)
	}

	facilities, err := newFacilities(db)
	if err != nil {
		return nil, err
	}

	players, err := newPlayers(db)
	if err != nil {
		return nil, err
	}

	staff, err := newStaff(db)
	if err != nil {
		return nil, err
	}

	return &localStore{
		db,
		facilities,
		players,
		staff,
	}, nil
}
