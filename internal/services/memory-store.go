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

package services

import (
	"context"
	"errors"
	"sync"
	"time"
)

/**
 *
 * Simple in-memory store implementation
 *
 **/

const (
	kCollectionPeriod = 5 * time.Minute
)

var (
	kErrorInvalidNamespace  = errors.New("invalid namespace")
	kErrorInvalidKey        = errors.New("invalid key")
	kErrorExpiredItem       = errors.New("expired item")
	kErrorItemAlreadyExists = errors.New("item already exists")
	kErrorItemChanged       = errors.New("item changed during refresh")
)

type memoryItem struct {
	purge time.Time
	value any
}

type memStore struct {
	scopes sync.Map
}

func NewMemoryStore(ctx context.Context) KeyValueStore {
	store := &memStore{}
	ticker := time.NewTicker(kCollectionPeriod)

	go func() {
		for {
			select {
			case <-ctx.Done():
				ticker.Stop()
				return
			case <-ticker.C:
				store.collect()
			}
		}
	}()

	return store
}

func (s *memStore) collect() {
	now := time.Now()

	s.scopes.Range(func(ns, value any) bool {
		scoped := value.(*sync.Map)
		scoped.Range(func(key, value any) bool {
			if value.(memoryItem).purge.Before(now) {
				_ = scoped.CompareAndDelete(key, value)
			}
			return true
		})
		return true
	})
}

func (store *memStore) Read(ns, key string) (any, error) {
	scoped, ok := store.scopes.Load(ns)
	if !ok {
		return nil, kErrorInvalidNamespace
	}

	item, ok := scoped.(*sync.Map).Load(key)
	if !ok {
		return nil, kErrorInvalidKey
	}

	if item.(memoryItem).purge.Before(time.Now()) {
		return nil, kErrorExpiredItem
	}

	return item.(memoryItem).value, nil
}

func (store *memStore) ReadAndRemove(ns, key string) (any, error) {
	scoped, ok := store.scopes.Load(ns)
	if !ok {
		return nil, kErrorInvalidNamespace
	}

	item, ok := scoped.(*sync.Map).LoadAndDelete(key)
	if !ok {
		return nil, kErrorInvalidKey
	}

	if item.(memoryItem).purge.Before(time.Now()) {
		return nil, kErrorExpiredItem
	}

	return item.(memoryItem).value, nil
}

func (store *memStore) CheckAndSet(ns, key string, value any, ttl time.Duration) error {
	scoped, ok := store.scopes.Load(ns)
	if !ok {
		scoped, _ = store.scopes.LoadOrStore(ns, new(sync.Map))
	}

	_, loaded := scoped.(*sync.Map).LoadOrStore(key, memoryItem{
		purge: time.Now().Add(ttl),
		value: value,
	})

	if loaded {
		return kErrorItemAlreadyExists
	}

	return nil
}

func (store *memStore) Set(ns, key string, value any, ttl time.Duration) error {
	scoped, ok := store.scopes.Load(ns)
	if !ok {
		scoped, _ = store.scopes.LoadOrStore(ns, new(sync.Map))
	}

	scoped.(*sync.Map).Store(key, memoryItem{
		purge: time.Now().Add(ttl),
		value: value,
	})

	return nil
}

func (store *memStore) Refresh(ns, key string, ttl time.Duration) error {
	scoped, ok := store.scopes.Load(ns)
	if !ok {
		return kErrorInvalidNamespace
	}

	item, ok := scoped.(*sync.Map).Load(key)
	if !ok {
		return kErrorInvalidKey
	}

	newItem := memoryItem{
		purge: time.Now().Add(ttl),
		value: item.(memoryItem).value,
	}

	if !scoped.(*sync.Map).CompareAndSwap(key, item, newItem) {
		return kErrorItemChanged
	}

	return nil
}

func (store *memStore) Remove(ns, key string) {
	if scoped, ok := store.scopes.Load(ns); ok {
		scoped.(*sync.Map).Delete(key)
	}
}
