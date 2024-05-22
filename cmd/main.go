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
	"log"
	"time"

	"shiftylogic.dev/hockey-tools/internal/services"
	"shiftylogic.dev/hockey-tools/internal/web"
)

func main() {
	ctx, shutdown := context.WithCancel(context.Background())

	go func() {
		defer shutdown()

		svcs := loadServices(ctx)
		config := loadConfig()

		options := append(
			selectMiddleware(config.Base),
			services.WithServices(svcs))

		// This needs to be the last thing added (as middleware) before we start
		// adding other handlers
		if config.Base.Profiler {
			options = append(options, web.WithProfiler())
		}

		options = append(options, getRoutes(config.Services)...)
		options = append(options, services.WithStaticRoutes(config.Base.Statics)...)

		router := web.NewRouter(options...)

		services.Start(config.Base, router)
	}()

	// Wait for the services to be stopped
	<-ctx.Done()

	// Allow a bit more time for the background goroutines to shutdown.
	// If they are paying attention to the Context passed to them, this
	// should be pretty quick.
	time.Sleep(time.Second)
	log.Print("Bye for realz!")
}

// func main() {
// 	store, err := local.Open("./.data/hockey.db")
// 	if err != nil {
// 		log.Fatalf("failed to open data store : %v\n", err)
// 	}
// 	defer store.Close()
//
// 	// Just grabbing the first "page" of results
// 	facilities, _, err := store.Facilities().List(0)
// 	if err != nil {
// 		log.Fatalf("failed to fetch facilities: %v\n", err)
// 	}
//
// 	for _, f := range facilities {
// 		log.Printf("Facilities (%d) - %s\n", f.ID(), f.Name())
// 	}
// }
