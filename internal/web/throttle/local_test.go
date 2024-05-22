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
	"fmt"
	"testing"
	"time"

	"shiftylogic.dev/hockey-tools/internal/test"
)

func TestLocalBasicIncrement(t *testing.T) {
	id := computeID("foo")
	tracker := NewLocalTracker(10 * time.Second)

	var i uint = 1
	for ; i <= 100; i++ {
		v, err := tracker.Increment(id, time.Now())
		test.NoError(t, err, "tracker increment failed")
		test.Require(t, v == i, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: %d)", v, i))
	}
}

func TestLocalRollover(t *testing.T) {
	id := computeID("bar")
	tracker := NewLocalTracker(10 * time.Second)
	now := time.Now().Truncate(10 * time.Second)

	var i uint = 1
	for ; i <= 20; i++ {
		v, err := tracker.Increment(id, now)
		test.NoError(t, err, "tracker increment failed")
		test.Require(t, v == i, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: %d)", v, i))
	}

	// Pretend we are just past when current window is over
	now = now.Add(10*time.Second + 3*time.Second)
	v, err := tracker.Get(id, now)
	test.NoError(t, err, "tracker increment failed")
	test.Require(t, v == 20, fmt.Sprintf("tracker value should be 20 (actual: %d)", v))

	// Decay the 'previous' window as well
	now = now.Add(10 * time.Second)
	v, err = tracker.Get(id, now)
	test.NoError(t, err, "tracker increment failed")
	test.Require(t, v == 0, "tracker value should be 0")

	// Does increment still work?
	v, err = tracker.Increment(id, now)
	test.NoError(t, err, "tracker increment failed")
	test.Require(t, v == 1, "tracker value should be 1")
}

func TestLocalDecay(t *testing.T) {
	id := computeID("bar")
	tracker := NewLocalTracker(4 * time.Second)
	now := time.Now().Truncate(4 * time.Second)

	_, err := tracker.Increment(id, now)
	test.NoError(t, err, "tracker increment failed")
	_, err = tracker.Increment(id, now)
	test.NoError(t, err, "tracker increment failed")
	_, err = tracker.Increment(id, now)
	test.NoError(t, err, "tracker increment failed")
	_, err = tracker.Increment(id, now)
	test.NoError(t, err, "tracker increment failed")

	v, err := tracker.Get(id, now)
	test.Require(t, v == 4, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: 4)", v))

	// Skip to next window
	now = now.Add(4 * time.Second)
	v, err = tracker.Increment(id, now)
	test.Require(t, v == 5, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: 5)", v))

	// Decay 25% of 'previous' window
	now = now.Add(time.Second)
	v, err = tracker.Get(id, now)
	test.Require(t, v == 4, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: 4)", v))

	// Decay 50% more of 'previous' window
	now = now.Add(2 * time.Second)
	v, err = tracker.Get(id, now)
	test.Require(t, v == 2, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: 2)", v))

	// Decay last of 'previous' window
	now = now.Add(time.Second)
	v, err = tracker.Get(id, now)
	test.Require(t, v == 1, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: 1)", v))
}

func TestLocalDecayWithPurge(t *testing.T) {
	id := computeID("bar")
	tracker := newLocalTracker(4*time.Second, 1*time.Millisecond)
	now := time.Now().Truncate(4 * time.Second)

	_, err := tracker.Increment(id, now)
	test.NoError(t, err, "tracker increment failed")
	_, err = tracker.Increment(id, now)
	test.NoError(t, err, "tracker increment failed")
	_, err = tracker.Increment(id, now)
	test.NoError(t, err, "tracker increment failed")
	_, err = tracker.Increment(id, now)
	test.NoError(t, err, "tracker increment failed")

	v, err := tracker.Get(id, now)
	test.Require(t, v == 4, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: 4)", v))

	// Skip to next window
	now = now.Add(4 * time.Second)
	v, err = tracker.Increment(id, now)
	test.Require(t, v == 5, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: 5)", v))

	// Decay 25% of 'previous' window
	now = now.Add(time.Second)
	v, err = tracker.Get(id, now)
	test.Require(t, v == 4, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: 4)", v))

	// Decay 50% more of 'previous' window
	now = now.Add(2 * time.Second)
	v, err = tracker.Get(id, now)
	test.Require(t, v == 2, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: 2)", v))

	// Decay last of 'previous' window
	now = now.Add(time.Second)
	v, err = tracker.Get(id, now)
	test.Require(t, v == 1, fmt.Sprintf("tracker value incorrect (Actual: %d, Expected: 1)", v))
}

func TestLocalPurge(t *testing.T) {
	tracker := newLocalTracker(100*time.Millisecond, 1*time.Millisecond)
	now := time.Now().Truncate(100 * time.Millisecond)

	tracker.Increment(1, now)
	test.Require(t, len(tracker.counters) == 1, "expected 1 tracked")
	tracker.Increment(2, now)
	test.Require(t, len(tracker.counters) == 2, "expected 2 tracked")

	now = now.Add(100 * time.Millisecond)
	tracker.Increment(1, now)
	test.Require(t, len(tracker.counters) == 2, "expected 2 tracked")
	tracker.Increment(3, now)
	test.Require(t, len(tracker.counters) == 3, "expected 3 tracked")

	now = now.Add(100 * time.Millisecond)
	test.Require(t, len(tracker.counters) == 3, "expected 3 tracked")
	tracker.Increment(1, now)
	tracker.Increment(4, now)
	test.Require(t, len(tracker.counters) == 4, "expected 4 tracked")

	now = now.Add(100 * time.Millisecond)
	tracker.Increment(1, now)
	v, _ := tracker.Get(2, now)
	test.Require(t, v == 0, "expected id '2' to be 0")
	test.Require(t, len(tracker.counters) == 3, "expected 3 tracked")

	now = now.Add(100 * time.Millisecond)
	v, _ = tracker.Get(1, now)
	test.Require(t, v == 1, "expected id '1' to be 1")
	v, _ = tracker.Get(3, now)
	test.Require(t, v == 0, "expected id '3' to be 0")
	v, _ = tracker.Get(4, now)
	test.Require(t, v == 0, "expected id '4' to be 0")
	test.Require(t, len(tracker.counters) == 2, "expected 1 tracked")

	now = now.Add(100 * time.Millisecond)
	v, _ = tracker.Get(1, now)
	test.Require(t, v == 0, "expected id '1' to be 0")
	v, _ = tracker.Get(4, now)
	test.Require(t, v == 0, "expected id '4' to be 0")
	test.Require(t, len(tracker.counters) == 1, "expected 0 tracked")

	now = now.Add(100 * time.Millisecond)
	test.Require(t, len(tracker.counters) == 1, fmt.Sprintf("expected 1 tracked (actual: %d)", len(tracker.counters)))

	now = now.Add(100 * time.Millisecond)
	v, _ = tracker.Get(1, now)
	test.Require(t, v == 0, "expected id '1' to be 0")
	test.Require(t, len(tracker.counters) == 0, fmt.Sprintf("expected 0 tracked (actual: %d)", len(tracker.counters)))
}
