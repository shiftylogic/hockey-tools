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
	"encoding/base64"
	"errors"
	"net/http"
	"strings"
)

var (
	kNoAuthorizationHeader = errors.New("no authorization header in request")
	kNotBasicAuthorization = errors.New("authorization header is not basic")
)

func ParseHttpAuthBasic(r *http.Request) (string, string, error) {
	val := r.Header.Get("Authorization")
	if val == "" {
		return "", "", kNoAuthorizationHeader
	}

	if strings.ToLower(val[:6]) != "basic " {
		return "", "", kNotBasicAuthorization
	}

	dval, err := base64.StdEncoding.DecodeString(val[6:])
	if err != nil {
		return "", "", err
	}

	uid, pwd, _ := strings.Cut(string(dval), ":")
	return uid, pwd, nil
}