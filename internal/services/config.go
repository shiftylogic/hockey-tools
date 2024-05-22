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
	"encoding/json"
	"io/fs"
	"log"
	"os"
	"path"

	"gopkg.in/yaml.v3"
	"shiftylogic.dev/hockey-tools/internal/web"
)

type Config struct {
	Address  string         `json:"address" yaml:"Address"`
	Port     int            `json:"port" yaml:"Port"`
	Logging  bool           `json:"logging" yaml:"Logging"`
	Profiler bool           `json:"profiler" yaml:"Profiler"`
	CORS     CORSConfig     `json:"cors" yaml:"CORS"`
	TLS      TLSConfig      `json:"tls" yaml:"TLS"`
	Statics  []StaticConfig `json:"statics" yaml:"Statics"`
}

type CORSConfig struct {
	AllowedOrigins   []string `json:"allowedOrigins" yaml:"AllowedOrigins"`
	AllowedMethods   []string `json:"allowedMethods" yaml:"AllowedMethods"`
	AllowedHeaders   []string `json:"allowedHeaders" yaml:"AllowedHeaders"`
	ExposedHeaders   []string `json:"exposedHeaders" yaml:"ExposedHeaders"`
	AllowCredentials bool     `json:"allowedCredentials" yaml:"AllowedCredentials"`
	MaxAge           int      `json:"maxAge" yaml:"MaxAge"`
}

type StaticConfig struct {
	Endpoint  string `json:"endpoint" yaml:"Endpoint"`
	LocalPath string `json:"localPath" yaml:"LocalPath"`
}

type TLSConfig struct {
	Certificate string `json:"certificate" yaml:"Certificate"`
	Key         string `json:"key" yaml:"Key"`
}

func DefaultConfig() Config {
	return Config{
		Address:  "localhost",
		Port:     80,
		Logging:  true,
		Profiler: false,
		CORS:     DefaultCORS(),
		TLS:      TLSConfig{},
	}
}

func DefaultCORS() CORSConfig {
	return CORSConfig{
		AllowedOrigins:   []string{"dude.man", "bar.none"},
		AllowedMethods:   []string{"GET", "HEAD"},
		AllowedHeaders:   []string{"Origin"},
		ExposedHeaders:   []string{},
		AllowCredentials: true,
		MaxAge:           300,
	}
}

func LoadConfig(configFile string, config any) {
	inFile, err := os.Open(configFile)
	if err != nil {
		log.Fatalf("[ERROR] Failed to load provided config file - %v", err)
	}

	switch path.Ext(configFile) {
	case ".yaml", ".yml":
		if err := yaml.NewDecoder(inFile).Decode(config); err != nil {
			log.Fatalf("[ERROR] Failed to parse / decode YAML config (%s) - %v", configFile, err)
		}
	case ".json":
		if err := json.NewDecoder(inFile).Decode(config); err != nil {
			log.Fatalf("[ERROR] Failed to parse / decode JSON config (%s) - %v", configFile, err)
		}
	default:
		panic("unknown config file format")
	}
}

/**
 *
 * Helper methods on CORSConfig struct
 *
 **/

func (cfg CORSConfig) Enabled() bool {
	return len(cfg.AllowedOrigins) > 0
}

func (cfg CORSConfig) Options() web.CorsOptions {
	return web.CorsOptions{
		AllowedOrigins:   cfg.AllowedOrigins,
		AllowedMethods:   cfg.AllowedMethods,
		AllowedHeaders:   cfg.AllowedHeaders,
		ExposedHeaders:   cfg.ExposedHeaders,
		AllowCredentials: cfg.AllowCredentials,
		MaxAge:           cfg.MaxAge,
	}
}

/**
 *
 * Helper methods on CORSConfig struct
 *
 **/

func (cfg StaticConfig) FS() fs.FS {
	return os.DirFS(cfg.LocalPath)
}

/**
 *
 * Helper methods on TLSConfig struct
 *
 **/

func (cfg TLSConfig) Enabled() bool {
	return cfg.Certificate != "" && cfg.Key != ""
}
