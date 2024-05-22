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
	"net/http"
	"strconv"
	"time"
)

const (
	kHeaderLimit      = "X-RateLimit-Limit"
	kHeaderPolicy     = "X-RateLimit-Policy"
	kHeaderRemaining  = "X-RateLimit-Remaining"
	kHeaderReset      = "X-RateLimit-Reset"
	kHeaderRetryAfter = "Retry-After"

	kDefaultRequestLimit = 100
	kDefaultWindowLength = 60 * time.Second
)

type LimitTracker interface {
	Get(id uint64, now time.Time) (uint, error)
	Increment(id uint64, now time.Time) (uint, error)
	WindowLength() time.Duration
}

type Throttler struct {
	RequestLimit    uint
	Tracker         LimitTracker
	RequestMapper   func(r *http.Request) (uint64, error)
	ExceededHandler http.HandlerFunc
}

func (t *Throttler) Handler(next http.Handler) http.Handler {
	mapper := t.RequestMapper
	if mapper == nil {
		mapper = func(r *http.Request) (uint64, error) {
			return 0, nil
		}
	}

	tracker := t.Tracker
	if tracker == nil {
		tracker = NewLocalTracker(kDefaultWindowLength)
	}

	limit := t.RequestLimit
	if limit == 0 {
		limit = kDefaultRequestLimit
	}

	exceeded := t.ExceededHandler
	if exceeded == nil {
		exceeded = func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, http.StatusText(http.StatusTooManyRequests), http.StatusTooManyRequests)
		}
	}

	// Precompute some re-used values
	limitValue := strconv.FormatUint(uint64(limit), 10)
	retryAfterValue := strconv.Itoa(int(tracker.WindowLength().Seconds()))
	policyValue := limitValue + ";w=" + retryAfterValue

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rid, err := mapper(r)
		if err != nil {
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			return
		}

		now := time.Now().UTC()
		window := tracker.WindowLength()
		windowLeft := uint64(now.Sub(now.Truncate(window)).Seconds())

		rate, err := tracker.Increment(rid, now)
		if err != nil {
			w.Header().Set(kHeaderRetryAfter, retryAfterValue)
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			return
		}

		w.Header().Set(kHeaderLimit, limitValue)
		w.Header().Set(kHeaderPolicy, policyValue)
		w.Header().Set(kHeaderRemaining, strconv.FormatUint(uint64(limit-rate), 10))
		w.Header().Set(kHeaderReset, strconv.FormatUint(windowLeft, 10))

		if limit < rate {
			exceeded(w, r)
			return
		}

		next.ServeHTTP(w, r)
	})
}
