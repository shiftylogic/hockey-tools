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

package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"log"
	"net/url"
	"strconv"
	"time"

	"shiftylogic.dev/hockey-tools/internal/helpers"
	"shiftylogic.dev/hockey-tools/internal/services"
)

const (
	kClientID    = "24C4853F-9398-41BD-B155-3333F181066B"
	kRedirectURI = "https://local.vroov.com:9443/auth-cb"

	kUser = "dude@intfoo.com"
	kPwd  = "1234test"

	kAuthGenRetries    = 10
	kAuthCodeSize      = 32
	kAuthRequestIDSize = 20

	kAuthCodeCacheNamespace = "auth_code"

	// QR Code generation
	kQRTokenSize      = 16
	kQRSecretSize     = 32
	kQRCacheNamespace = "qrc"
)

var (
	kBadUserPasswordError = errors.New("invalid user or password")
)

type fixedAuthorizer struct {
	store services.KeyValueStore
}

func (v *fixedAuthorizer) GenerateAuthorizationRequest(data services.AuthCodeData, ttl time.Duration) (string, error) {
	var err error

	for i := 0; i < kAuthGenRetries; i++ {
		code, err := helpers.GenerateStringSecure(kAuthCodeSize, helpers.AlphaNumeric)
		if err != nil {
			return "", err
		}

		err = v.store.CheckAndSet(kAuthCodeCacheNamespace, code, data, ttl)
		if err == nil {
			return code, nil
		}
	}

	return "", err
}

func (v *fixedAuthorizer) GenerateQRRequest(ttl time.Duration) (string, string, string, error) {
	key, err := helpers.GenerateStringSecure(kQRSecretSize, helpers.AlphaNumeric)
	if err != nil {
		return "", "", "", err
	}

	var token string
	for i := 0; i < kAuthGenRetries; i++ {
		token, err = helpers.GenerateStringSecure(kQRTokenSize, helpers.AlphaNumeric)
		if err != nil {
			return "", "", "", err
		}

		err = v.store.CheckAndSet(kQRCacheNamespace, token, key, ttl)
		if err == nil {
			break
		}
	}

	if err != nil {
		return "", "", "", err
	}

	ts := strconv.FormatInt(time.Now().Unix(), 10)

	hm := hmac.New(sha256.New, []byte(key))
	hm.Write([]byte(ts))
	hm.Write([]byte(token))
	hash := hm.Sum(nil)

	return ts, token, hex.EncodeToString(hash), nil
}

func (v *fixedAuthorizer) Authenticate(user, pwd string) (string, error) {
	res := subtle.ConstantTimeCompare([]byte(kUser), []byte(user))
	res += subtle.ConstantTimeCompare([]byte(kPwd), []byte(pwd))
	if res != 2 {
		return "", kBadUserPasswordError
	}

	return "1", nil
}

func (v *fixedAuthorizer) ValidateClient(cid, redir string) bool {
	redir, err := url.QueryUnescape(redir)
	if err != nil {
		log.Printf("Failed to unescape redirect URI - %v", err)
		return false
	}

	res := subtle.ConstantTimeCompare([]byte(kClientID), []byte(cid))
	res += subtle.ConstantTimeCompare([]byte(kRedirectURI), []byte(redir))

	return res == 2
}
