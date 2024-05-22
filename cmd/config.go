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
	"shiftylogic.dev/hockey-tools/internal/helpers"
	"shiftylogic.dev/hockey-tools/internal/services"
	"shiftylogic.dev/hockey-tools/internal/services/auth"
)

const (
	kConfigFileEnvKey = "SL_CONFIG"
)

type ServicesConfig struct {
	Auth auth.Config `json:"auth" yaml:"Auth"`
}

type AppConfig struct {
	Base     services.Config `json:"root" yaml:"Root"`
	Services ServicesConfig  `json:"services" yaml:"Services"`
}

func loadConfig() AppConfig {
	config := AppConfig{
		services.DefaultConfig(),
		ServicesConfig{
			Auth: auth.DefaultConfig(),
		},
	}

	if configFile := helpers.ReadEnvWithDefault(kConfigFileEnvKey, ""); configFile != "" {
		services.LoadConfig(configFile, &config)
	}

	return config
}
