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
	"crypto/tls"
	"log"
	"net/http"
	"time"
)

type ServerOptionFunc func(*Server)

/**
 *
 * All functions below here are simple exported funclets for
 * doing "functional" building of the HTTP Server.
 *
 **/

func WithAddress(addr string) ServerOptionFunc {
	return func(s *Server) {
		s.Addr = addr
	}
}

func WithHandler(handler http.Handler) ServerOptionFunc {
	return func(s *Server) {
		s.Handler = handler
	}
}

func WithShutdownTimeout(timeout time.Duration) ServerOptionFunc {
	return func(s *Server) {
		s.ShutdownTimeout = timeout
	}
}

func WithTLS(cert, key string) ServerOptionFunc {
	return func(s *Server) {
		cert, err := tls.LoadX509KeyPair(cert, key)
		if err != nil {
			log.Fatalf("Failed to load TLS key-pair: %v\n", err)
		}

		s.TLSConfig = &tls.Config{
			Certificates: []tls.Certificate{cert},
		}
	}
}
