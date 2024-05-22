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
	"context"

	"shiftylogic.dev/hockey-tools/internal/services"
	"shiftylogic.dev/hockey-tools/internal/services/auth"
	"shiftylogic.dev/hockey-tools/internal/web"
)

func loadServices(ctx context.Context) services.Services {
	kvs := services.NewMemoryStore(ctx)

	return &services.ServicesContainer{
		EphemeralStore: &services.SimpleDataStore{
			KVS: kvs,
		},
		Authy: &fixedAuthorizer{
			store: kvs,
		},
	}
}

func selectMiddleware(config services.Config) []web.RouterOptionFunc {
	options := []web.RouterOptionFunc{
		web.WithLogging(),
		web.WithPanicRecovery(),
		web.WithNoIFrame(),
		web.WithNoCache(), // TODO: Remove this at some point later
	}

	if config.CORS.Enabled() {
		options = append(options, web.WithCors(config.CORS.Options()))
	}

	return options
}

func getRoutes(config ServicesConfig) []web.RouterOptionFunc {
	return []web.RouterOptionFunc{
		auth.WithOAuth2(config.Auth),
	}
}
