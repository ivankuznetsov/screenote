package cli

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os/exec"
	"runtime"
	"time"

	appconfig "github.com/ivankuznetsov/screenote/internal/config"
	"github.com/ivankuznetsov/screenote/internal/screenote"
	"github.com/spf13/cobra"
)

const oauthScope = "mcp_read mcp_write"

var openBrowser = func(rawURL string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", rawURL)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", rawURL)
	default:
		cmd = exec.Command("xdg-open", rawURL)
	}
	return cmd.Start()
}

func (a *app) loginCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "login",
		Short: "Authorize the CLI with OAuth",
		Args:  rejectArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			resolved, err := a.resolvedConfig()
			if err != nil {
				return err
			}
			if resolved.BaseURL == "" {
				return usageError("missing_base_url", "base URL is required; set --base-url, SCREENOTE_BASE_URL, or config base_url")
			}
			credentials, err := a.runLogin(cmd.Context(), resolved.BaseURL)
			if err != nil {
				return err
			}
			path := defaultConfigPath(a.configPath)
			values, err := appconfig.LoadExpanded(path)
			if err != nil {
				return err
			}
			values.Login = credentials
			if values.BaseURL == "" {
				values.BaseURL = resolved.BaseURL
			}
			if err := appconfig.Save(path, values); err != nil {
				return err
			}
			return writeJSON(a.stdout, map[string]any{"ok": true, "path": path})
		},
	}
}

func (a *app) logoutCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "logout",
		Short: "Remove stored OAuth login credentials",
		Args:  rejectArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			path := defaultConfigPath(a.configPath)
			values, err := appconfig.LoadExpanded(path)
			if err != nil {
				return err
			}
			values.Login = nil
			if err := appconfig.Save(path, values); err != nil {
				return err
			}
			return writeJSON(a.stdout, map[string]any{"ok": true, "path": path})
		},
	}
}

func (a *app) runLogin(ctx context.Context, baseURL string) (*appconfig.LoginCredentials, error) {
	metadata, err := screenote.DiscoverOAuth(ctx, baseURL, a.httpClient)
	if err != nil {
		return nil, err
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	defer listener.Close()

	redirectURI := "http://" + listener.Addr().String() + "/callback"
	registration, err := screenote.RegisterOAuthClient(ctx, metadata, redirectURI, a.httpClient)
	if err != nil {
		return nil, err
	}
	verifier, err := screenote.RandomToken(32)
	if err != nil {
		return nil, err
	}
	state, err := screenote.RandomToken(24)
	if err != nil {
		return nil, err
	}
	authURL, err := screenote.AuthorizationURL(metadata, registration.ClientID, redirectURI, verifier, state, oauthScope)
	if err != nil {
		return nil, err
	}

	result := make(chan callbackResult, 1)
	server := &http.Server{Handler: callbackHandler(state, result)}
	go func() {
		_ = server.Serve(listener)
	}()
	defer server.Shutdown(context.Background())

	if err := openBrowser(authURL); err != nil {
		fmt.Fprintf(a.stderr, "Open this URL to continue login: %s\n", authURL)
	}

	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case received := <-result:
		if received.err != nil {
			return nil, received.err
		}
		response, err := screenote.ExchangeCode(ctx, metadata, registration.ClientID, redirectURI, received.code, verifier, a.httpClient)
		if err != nil {
			return nil, err
		}
		return &appconfig.LoginCredentials{
			AccessToken:  response.AccessToken,
			RefreshToken: response.RefreshToken,
			ExpiresAt:    screenote.ExpiresAt(response, time.Now()),
			ClientID:     registration.ClientID,
			BaseURL:      baseURL,
			Issuer:       metadata.Issuer,
		}, nil
	}
}

type callbackResult struct {
	code string
	err  error
}

func callbackHandler(expectedState string, result chan<- callbackResult) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/callback" {
			http.NotFound(w, r)
			return
		}
		query := r.URL.Query()
		if query.Get("state") != expectedState {
			result <- callbackResult{err: usageError("invalid_oauth_state", "OAuth callback state did not match")}
			http.Error(w, "Invalid OAuth state", http.StatusBadRequest)
			return
		}
		if errText := query.Get("error"); errText != "" {
			result <- callbackResult{err: authError("oauth_error", errText)}
			http.Error(w, errText, http.StatusBadRequest)
			return
		}
		code := query.Get("code")
		if code == "" {
			result <- callbackResult{err: usageError("missing_oauth_code", "OAuth callback did not include an authorization code")}
			http.Error(w, "Missing OAuth code", http.StatusBadRequest)
			return
		}
		result <- callbackResult{code: code}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = w.Write([]byte("Screenote login complete. You can close this window."))
	})
}

func callbackURL(base string, values url.Values) string {
	u, _ := url.Parse(base)
	u.RawQuery = values.Encode()
	return u.String()
}
