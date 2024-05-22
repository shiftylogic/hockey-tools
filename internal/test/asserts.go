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

package test

import (
	"reflect"
	"testing"
)

func NoError(t *testing.T, err error, msg string) {
	t.Helper()
	if err != nil {
		t.Fatalf("Expected no error (got: %v) - %s", err, msg)
	}
}

func AnyError(t *testing.T, err error, msg string) {
	t.Helper()
	if err == nil {
		t.Fatalf("Expected error - %s", msg)
	}
}

func SpecificError(t *testing.T, err error, expected error, msg string) {
	t.Helper()
	if err != expected {
		t.Fatalf("Expected error (expected: %v, got: %v) - %s", expected, err, msg)
	}
}

func Require(t *testing.T, condition bool, msg string) {
	t.Helper()
	if !condition {
		t.Fatalf(msg)
	}
}

func Expect(t *testing.T, expected, actual any, msg string) {
	t.Helper()
	if !reflect.DeepEqual(expected, actual) {
		t.Fatalf("Value '%v' does not match expected '%v': %s", actual, expected, msg)
	}
}

func ExpectBits(t *testing.T, expected, actual []uint8, count uint, msg string) {
	t.Helper()

	if len(actual) < len(expected) {
		t.Fatal("Actual slice too short")
	}

	n := count / 8
	var i uint = 0
	for ; i < n; i++ {
		if actual[i] != expected[i] {
			t.Fatalf("Actual byte #%d (%x) does not match expected value (%x): %s", i+1, actual[i], expected[i], msg)
		}
	}

	// If this was a multiple of 8 bits, the last check is not needed
	if count%8 == 0 {
		return
	}

	// The last byte needs to be masked for appropriate bit count
	var mask uint8 = 0xFF << (8 - (count % 8))
	am := actual[n] & mask
	if am != expected[n] {
		t.Fatalf("Last byte (%x) does not match expected value (%x): %s", am, expected[n], msg)
	}
}
