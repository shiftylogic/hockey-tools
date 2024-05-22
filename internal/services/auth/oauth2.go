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
	"html/template"
	"log"
	"net/http"
	"os"

	"shiftylogic.dev/hockey-tools/internal/services"
	"shiftylogic.dev/hockey-tools/internal/web"
)

const (
	kAuthorizeRoute = "/authorize"
	kLoginRoute     = "/login"
	kTokenRoute     = "/token"
	kQRImageRoute   = "/qrcode"

	// UI Templates
	kLoginTemplate = "login.html"

	// Error strings for auth callback
	kAccessDeniedError       = "access_denied"
	kServerError             = "server_error"
	kUnsupportedGrantType    = "unsupported_grant_type"
	kUnsupportedResponseType = "unsupported_response_type"
)

type loginViewData struct {
	ClientID        string
	RedirectURI     string
	Scope           string
	State           string
	Challenge       string
	ChallengeMethod string

	QREnabled bool
}

func WithOAuth2(config Config) web.RouterOptionFunc {
	templates := template.Must(template.ParseFS(os.DirFS(config.Templates), "*.html"))

	return func(root web.Router) {
		r := web.NewRouter()

		r.With(web.NoIFrame).Get(kAuthorizeRoute, Authorize(templates, config))
		r.Get(kLoginRoute, Login(config))
		r.Post(kLoginRoute, Login(config))
		r.Post(kTokenRoute, Token(config))

		if config.QRScan.Enabled {
			r.Get(kQRImageRoute, QRGenerator(config.QRScan))
			// r.Get("/do-a-thing", DoThing(config.QRScan.TTL))
		}

		root.Mount(config.Path, r)
	}
}

func Authorize(templates *template.Template, config Config) func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		data := loginViewData{
			ClientID:        r.URL.Query().Get("client_id"),
			RedirectURI:     r.URL.Query().Get("redirect_uri"),
			Scope:           r.URL.Query().Get("scope"),
			State:           r.URL.Query().Get("state"),
			Challenge:       r.URL.Query().Get("code_challenge"),
			ChallengeMethod: r.URL.Query().Get("code_challenge_method"),
			QREnabled:       config.QRScan.Enabled,
		}

		svcs := services.ServicesFromContext(r.Context())

		if !svcs.Authorizer().ValidateClient(data.ClientID, data.RedirectURI) {
			log.Print("[Error] Invalid client and / or redirect URL in authorize call.")
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		if rtype := r.URL.Query().Get("response_type"); rtype != "code" {
			log.Print("[Error] Unsupported response_type in authorization request.")
			redirectAuthError(w, r, data.RedirectURI, kUnsupportedResponseType, data.State)
			return
		}

		if err := templates.ExecuteTemplate(w, kLoginTemplate, data); err != nil {
			log.Printf("[Error] Failed to execute 'login' template - %v", err)
			redirectAuthError(w, r, data.RedirectURI, kServerError, data.State)
			return
		}
	}
}

func Login(config Config) func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		svcs := services.ServicesFromContext(r.Context())
		cid := r.FormValue("client_id")
		data := services.AuthCodeData{
			UID:             "",
			RedirectURI:     r.FormValue("redirect_uri"),
			Scope:           r.FormValue("scope"),
			State:           r.FormValue("state"),
			Challenge:       r.FormValue("challenge"),
			ChallengeMethod: r.FormValue("challenge_mode"),
		}

		if !svcs.Authorizer().ValidateClient(cid, data.RedirectURI) {
			log.Print("[Error] Invalid client and / or redirect URL in login call.")
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		user := r.FormValue("user")
		pwd := r.FormValue("pwd")

		uid, err := svcs.Authorizer().Authenticate(user, pwd)
		if err != nil {
			log.Printf("[Error] Authentication failed - %v", err)
			redirectAuthError(w, r, data.RedirectURI, kAccessDeniedError, data.State)
			return
		}

		data.UID = uid
		code, err := svcs.Authorizer().GenerateAuthorizationRequest(data, config.CodeTTL)
		if err != nil {
			log.Printf("[Error] Failed to generate authorization code - %v", err)
			redirectAuthError(w, r, data.RedirectURI, kServerError, data.State)
			return
		}

		redirectAuthSuccess(w, r, data.RedirectURI, code, data.State)
	}
}

func Token(config Config) func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "https://www.bing.com", http.StatusFound)
	}
}

/**
 * OAuth2 callback redirection helpers
 **/

func redirectAuthSuccess(w http.ResponseWriter, r *http.Request, redir, code, state string) {
	http.Redirect(w, r, fmt.Sprintf("%s?code=%s&state=%s", redir, code, state), http.StatusFound)
}

func redirectAuthError(w http.ResponseWriter, r *http.Request, redir, errS, state string) {
	http.Redirect(w, r, fmt.Sprintf("%s?error=%s&state=%s", redir, errS, state), http.StatusFound)
}

/**
 * TODO: Remove
 * This is just for playing with the QR Code generator
 **/
/*
func DoThing(ttl time.Duration) func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		ts := r.URL.Query().Get("ts")
		token := r.URL.Query().Get("tk")
		h := r.URL.Query().Get("h")

		tsSecs, err := strconv.ParseInt(ts, 10, 64)
		if err != nil {
			log.Printf("[Error] Timestamp parse failure - %v", err)
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		if time.Now().Sub(time.Unix(tsSecs, 0)) > ttl {
			log.Printf("[Error] Token expired")
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		svcs := services.ServicesFromContext(r.Context())
		if svcs == nil {
			log.Print("[Error] Failed to acquire active services")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			return
		}

		key, err := svcs.Ephemeral().KeyValues().ReadAndRemove("qrc", token)
		if err != nil {
			log.Printf("[Error] Failed to fetch key associated with token (%s) - %v", token, err)
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		hm := hmac.New(sha256.New, []byte(key.(string)))
		hm.Write([]byte(ts))
		hm.Write([]byte(token))
		computedH := hm.Sum(nil)

		expectedH, err := hex.DecodeString(h)
		if err != nil {
			log.Printf("[Error] Timestamp parse failure - %v", err)
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprintf(w, "QR Code Scanned:\n")
		fmt.Fprintf(w, "  => Timestamp: %v (%s)\n", time.Unix(tsSecs, 0), ts)
		fmt.Fprintf(w, "  => Token: %s\n", token)
		fmt.Fprintf(w, "  => Hash: %s\n", h)
		fmt.Fprintf(w, "  => Verified? %v\n", hmac.Equal(computedH, expectedH))
	}
}
*/
