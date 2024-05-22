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
	"log"
	"net/http"

	"github.com/go-chi/chi/v5"
)

/**
 *
 * NOTE: This mini-module just exports types from the tiny
 *       chi library to (semi-)mask what is being used.
 *
 **/

type MiddlewareFuncs = chi.Middlewares
type Router = chi.Router

/**
 *
 * Returns a router after applying the option funclets.
 *
 */
func NewRouter(options ...RouterOptionFunc) Router {
	r := chi.NewRouter()

	for _, fn := range options {
		fn(r)
	}

	return r
}

func DumpRouter(r Router) {
	walker := func(method, route string, h http.Handler, mws ...func(http.Handler) http.Handler) error {
		log.Printf("[Route] %s %s\n", method, route)
		return nil
	}

	if err := chi.Walk(r, walker); err != nil {
		log.Fatalf("[ERROR] Failed to walk the router - %v", err)
	}
}
