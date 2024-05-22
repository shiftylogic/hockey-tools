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
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

const (
	kDefaultMaxHeaderBytes = 1 << 20

	kDefaultIdleTimeout       = 60 * time.Second
	kDefaultReadTimeout       = 30 * time.Second
	kDefaultReadHeaderTimeout = 10 * time.Second
	kDefaultWriteTimeout      = 30 * time.Second

	kDefaultShutdownTimeout = 30 * time.Second
)

type Server struct {
	http.Server

	ShutdownTimeout time.Duration
}

/**
 *
 * The Start / StartWithOptions functions are blocking calls.
 *
 * They creates the server, set up graceful shutdown, and
 * then listen until a termination signal triggers a shutdown.
 *
 **/

func Start() {
	startCore(makeDefaultServer())
}

func StartWithOptions(options ...ServerOptionFunc) {
	srv := makeDefaultServer()

	for _, fn := range options {
		fn(srv)
	}

	startCore(srv)
}

func makeDefaultServer() *Server {
	return &Server{
		http.Server{
			MaxHeaderBytes: kDefaultMaxHeaderBytes,

			IdleTimeout:       kDefaultIdleTimeout,
			ReadTimeout:       kDefaultReadTimeout,
			ReadHeaderTimeout: kDefaultReadHeaderTimeout,
			WriteTimeout:      kDefaultWriteTimeout,
		},

		// Custom properties in "Server" wrapper
		kDefaultShutdownTimeout,
	}
}

func startCore(server *Server) {
	ctx := setupContextWithShutdown(server)

	// This will listen and block until a shutdown is triggered.
	if server.TLSConfig == nil {
		startWithoutTLS(server)
	} else {
		startWithTLS(server)
	}

	// Once the server is shutdown, we wait until the server
	// context is complete to terminate
	<-ctx.Done()
}

func startWithoutTLS(server *Server) {
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Server listen failed: %v\n", err)
	}
}

func startWithTLS(server *Server) {
	if err := server.ListenAndServeTLS("", ""); err != http.ErrServerClosed {
		log.Fatalf("Server listen failed: %v\n", err)
	}
}

func setupContextWithShutdown(server *Server) context.Context {
	ctx, stop := context.WithCancel(context.Background())

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		// Wait for a signal to stop server
		<-sig

		stopCtx, _ := context.WithTimeout(ctx, server.ShutdownTimeout)
		go func() {
			<-stopCtx.Done()
			if stopCtx.Err() == context.DeadlineExceeded {
				log.Fatal("Shutdown timed out. Terminating.")
			}
		}()

		if err := server.Shutdown(stopCtx); err != nil {
			log.Fatalf("Server shutdown failed: %v\n", err)
		}

		stop()
	}()

	return ctx
}
