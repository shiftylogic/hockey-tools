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

package throttle

import (
	"sync"
	"time"
)

const (
	kPurgeDelay = 5 * time.Minute
)

type counter struct {
	current  uint
	previous uint
	window   int64 // in UNIX milliseconds
}

type localTracker struct {
	counters     map[uint64]*counter
	windowLength time.Duration
	purgeDelay   time.Duration
	purgeTime    time.Time
	mu           sync.Mutex
}

func NewLocalTracker(windowLength time.Duration) LimitTracker {
	return newLocalTracker(windowLength, kPurgeDelay)
}

func newLocalTracker(windowLength, purgeDelay time.Duration) *localTracker {
	return &localTracker{
		counters:     make(map[uint64]*counter),
		windowLength: windowLength,
		purgeDelay:   purgeDelay,
		purgeTime:    time.Now().UTC().Add(purgeDelay),
	}
}

func (tracker *localTracker) Get(id uint64, now time.Time) (uint, error) {
	scopedWindow := now.Truncate(tracker.windowLength)
	previousWindow := scopedWindow.Add(-tracker.windowLength)

	tracker.mu.Lock()
	defer tracker.mu.Unlock()

	// While we have the lock, check to see if we need to run the purge logic
	// to clean up unused entries
	tracker.purge(now)

	v, ok := tracker.counters[id]
	if !ok {
		return 0, nil
	}

	if scopedWindow.UnixMilli() == v.window {
		elapsed := now.Sub(scopedWindow)
		return tracker.computeSlidingRate(v.current, v.previous, elapsed), nil
	}

	if v.window == previousWindow.UnixMilli() {
		return v.current, nil
	} else {
		return 0, nil
	}
}

func (tracker *localTracker) Increment(id uint64, now time.Time) (uint, error) {
	scopedWindow := now.Truncate(tracker.windowLength)
	previousWindow := scopedWindow.Add(-tracker.windowLength)
	elapsed := now.Sub(scopedWindow)

	tracker.mu.Lock()
	defer tracker.mu.Unlock()

	// While we have the lock, check to see if we need to run the purge logic
	// to clean up unused entries
	tracker.purge(now)

	v, ok := tracker.counters[id]
	if !ok {
		// New entry
		tracker.counters[id] = &counter{
			current:  1,
			previous: 0,
			window:   scopedWindow.UnixMilli(),
		}
		return 1, nil
	}

	if scopedWindow.UnixMilli() == v.window {
		// Simple increment in the current window
		v.current++
	} else {
		if v.window == previousWindow.UnixMilli() {
			// If the current count is outside the window but "recent" then move to previous to keep.
			v.previous = v.current
		} else {
			// The counter is old enough for a full reset
			v.previous = 0
		}

		v.current = 1
		v.window = scopedWindow.UnixMilli()
	}

	return tracker.computeSlidingRate(v.current, v.previous, elapsed), nil
}
func (tracker *localTracker) WindowLength() time.Duration {
	return tracker.windowLength
}

func (tracker *localTracker) computeSlidingRate(cv, pv uint, elapsed time.Duration) uint {
	window := tracker.windowLength.Milliseconds()
	decay := float64(window-elapsed.Milliseconds()) / float64(window)
	return uint(float64(pv)*decay) + cv
}

func (tracker *localTracker) purge(now time.Time) {
	if tracker.purgeTime.After(now) {
		return
	}

	purgeTarget := now.Add(-3 * tracker.windowLength).UnixMilli()

	for k, v := range tracker.counters {
		if v.window <= purgeTarget {
			delete(tracker.counters, k)
		}
	}

	tracker.purgeTime = now.Add(tracker.purgeDelay)
}
