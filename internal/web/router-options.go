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

package web

import (
	"io/fs"
	"net/http"
	"path"
	"strings"

	"github.com/go-chi/chi/v5/middleware"
)

type RouterOptionFunc func(Router)

/**
 *
 * All functions below here are simple exported funclets for
 * doing "functional" building of the Router.
 *
 **/

func WithAllowContentEncoding(encodings ...string) RouterOptionFunc {
	return func(r Router) {
		r.Use(middleware.AllowContentEncoding(encodings...))
	}
}

func WithAllowContentType(types ...string) RouterOptionFunc {
	return func(r Router) {
		r.Use(middleware.AllowContentType(types...))
	}
}

func WithCleanPath() RouterOptionFunc {
	return func(r Router) {
		r.Use(middleware.CleanPath)
	}
}

func WithCompression(types ...string) RouterOptionFunc {
	return func(r Router) {
		r.Use(middleware.Compress(5, types...))
	}
}

func WithHeartbeat(path string) RouterOptionFunc {
	return func(r Router) {
		r.Use(middleware.Heartbeat(path))
	}
}

func WithNoCache() RouterOptionFunc {
	return func(r Router) {
		r.Use(middleware.NoCache)
	}
}

func WithNoIFrame() RouterOptionFunc {
	return func(r Router) {
		r.Use(NoIFrame)
	}
}

func WithProfiler() RouterOptionFunc {
	return func(r Router) {
		r.Mount("/debug", middleware.Profiler())
	}
}

func WithPanicRecovery() RouterOptionFunc {
	return func(r Router) {
		r.Use(middleware.Recoverer)
	}
}

func WithLogging() RouterOptionFunc {
	return func(r Router) {
		r.Use(middleware.Logger)
	}
}

func WithStaticFiles(endpoint, prefix string, root fs.FS) RouterOptionFunc {
	if strings.ContainsAny(endpoint, "{}*") {
		panic("endpoint path cannot have any URL parameters")
	}

	return func(r Router) {
		route := path.Join(endpoint, "*")
		stripped := path.Join(prefix, endpoint)
		handler := http.StripPrefix(stripped, http.FileServer(http.FS(root)))

		r.With(NoDirectoryListing).Get(route, func(w http.ResponseWriter, r *http.Request) {
			handler.ServeHTTP(w, r)
		})
	}
}
