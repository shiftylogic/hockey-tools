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

package auth

import (
	"time"
)

const (
	kDefaultQRCodeTTL = 2 * time.Minute
	kDefaultCodeTTL   = 1 * time.Minute
	kDefaultTokenTTL  = 30 * time.Minute
)

type Config struct {
	Path      string `json:"path" yaml:"Path"`
	Secret    string `json:"secret" yaml:"Secret"`
	Templates string `json:"templates" yaml:"Templates"`

	CodeTTL  time.Duration `json:"codeTTL" yaml:"CodeTTL"`
	TokenTTL time.Duration `json:"tokenTTL" yaml:"tokenTTL"`

	QRScan QRScanConfig `json:"qrscan" yaml:"QRScan"`
}

type QRScanConfig struct {
	Enabled bool          `json:"enabled" yaml:"Enabled"`
	Prefix  string        `json:"prefix" yaml:"Prefix"`
	TTL     time.Duration `json:"ttl" yaml:"TTL"`
}

func DefaultConfig() Config {
	return Config{
		Path:      "",
		Secret:    "",
		Templates: "",

		CodeTTL:  kDefaultCodeTTL,
		TokenTTL: kDefaultTokenTTL,

		QRScan: QRScanConfig{
			Enabled: false,
			Prefix:  "",
			TTL:     kDefaultQRCodeTTL,
		},
	}
}
