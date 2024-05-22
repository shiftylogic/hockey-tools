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

const (
	MaxUInt = ^uint(0)
	MinUInt = 0
	MaxInt  = int(MaxUInt >> 1)
	MinInt  = -MaxInt - 1

	MaxUInt32 = ^uint32(0)
	MinUInt32 = 0
	MaxInt32  = int32(MaxUInt32 >> 1)
	MinInt32  = -MaxInt32 - 1

	MaxUInt64 = ^uint64(0)
	MinUInt64 = 0
	MaxInt64  = int64(MaxUInt64 >> 1)
	MinInt64  = -MaxInt64 - 1
)
