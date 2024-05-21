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

package data

import (
	"time"
)

type ScoringEvent interface {
	Timestamp() int
	TeamID() EntityID
	Scorer() EntityID
	PrimaryAssist() EntityID
	SecondaryAssist() EntityID
	Other() []EntityID
	Defenders() []EntityID
}

type ScoringEvents interface {
	ByGame(game EntityID) []ScoringEvent
}

type PenaltyEvent interface {
	Timestamp() int
	TeamID() EntityID
	Committer() EntityID
	Minutes() int
	Infraction() string
	ServedBy() EntityID
}

type PenaltyEvents interface {
	ByGame(game EntityID) []PenaltyEvent
}

type GameOverview interface {
	ID() EntityID
	Tags() []string
	When() time.Time
	Where() EntityID
	Home() EntityID
	Visitor() EntityID
	HomeScore() int
	VisitorScore() int
}

type GameDetails interface {
	ID() EntityID
	Overview() GameOverview
	PeriodLengths() []int
	Goals() []ScoringEvent
	Penalties() []PenaltyEvent
}

type Games interface {
	List(token int64) ([]GameOverview, int64)
	ByTeam(id EntityID) []GameOverview
	DetailsByGame(game EntityID) GameDetails
}
