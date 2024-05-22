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
	"fmt"
	"log"
	"net/http"

	qrcode "github.com/skip2/go-qrcode"
	"shiftylogic.dev/hockey-tools/internal/services"
)

const (
	kQRImageSize              = 512
	kQRErrorCorrectionQuality = qrcode.Low
)

func QRGenerator(qr QRScanConfig) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		svcs := services.ServicesFromContext(r.Context())
		ts, token, hash, err := svcs.Authorizer().GenerateQRRequest(qr.TTL)
		if err != nil {
			log.Printf("[Error] Failed to generate QR request - %v", err)
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			return
		}

		code, err := qrcode.New(
			fmt.Sprintf("%s?ts=%s&tk=%s&h=%x", qr.Prefix, ts, token, hash),
			kQRErrorCorrectionQuality,
		)
		if err != nil {
			log.Printf("[Error] Failed to generate QR Code - %v", err)
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			return
		}

		png, err := code.PNG(kQRImageSize)
		if err != nil {
			log.Printf("[Error] Failed to generate QR Code PNG - %v", err)
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "image/png")
		w.Write(png)
	}
}
