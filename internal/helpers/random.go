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

package helpers

import (
	"crypto/rand"
	"math/big"
)

const (
	AlphaLower = "abcdefghijklmnopqrstuvwxyz"
	AlphaUpper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	Numeric    = "0123456789"

	Alpha        = AlphaLower + AlphaUpper
	AlphaNumeric = Alpha + Numeric
)

func GenerateBytesSecure(count int) ([]byte, error) {
	b := make([]byte, count)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}

	return b, nil
}

func GenerateStringSecure(count int, chars string) (string, error) {
	max := big.NewInt(int64(len(chars)))
	s := make([]byte, count)

	for i := 0; i < count; i++ {
		num, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}

		s[i] = chars[num.Int64()]
	}

	return string(s), nil
}
