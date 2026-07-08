package cli

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"time"

	appconfig "github.com/ivankuznetsov/screenote/internal/config"
	"github.com/ivankuznetsov/screenote/internal/screenote"
	"github.com/spf13/cobra"
)

type app struct {
	stdin       io.Reader
	stdout      io.Writer
	stderr      io.Writer
	httpClient  *http.Client
	flags       appconfig.Values
	configPath  string
	interactive bool
}

func Execute(ctx context.Context, args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	a := &app{stdin: stdin, stdout: stdout, stderr: stderr}
	cmd := a.rootCommand(ctx)
	cmd.SetArgs(args)
	if err := cmd.ExecuteContext(ctx); err != nil {
		return writeError(stderr, err)
	}
	return ExitOK
}

func NewTestCommand(ctx context.Context, stdin io.Reader, stdout, stderr io.Writer, httpClient *http.Client) *cobra.Command {
	a := &app{stdin: stdin, stdout: stdout, stderr: stderr, httpClient: httpClient}
	return a.rootCommand(ctx)
}

func (a *app) rootCommand(_ context.Context) *cobra.Command {
	root := &cobra.Command{
		Use:           "screenote",
		Short:         "Screenote REST CLI",
		Args:          rejectArgs,
		RunE:          showHelp,
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.SetFlagErrorFunc(func(_ *cobra.Command, err error) error {
		return usageError("invalid_flag", err.Error())
	})
	root.PersistentFlags().StringVar(&a.flags.Token, "token", "", "Screenote OAuth bearer token")
	root.PersistentFlags().StringVar(&a.flags.BaseURL, "base-url", "", "Screenote base URL")
	root.PersistentFlags().StringVar(&a.flags.Project, "project", "", "Screenote project ID")
	root.PersistentFlags().StringVar(&a.configPath, "config", "", "Config file path")
	root.PersistentFlags().BoolVar(&a.interactive, "interactive", false, "Allow interactive prompts")

	root.AddCommand(
		a.configCommand(),
		a.loginCommand(),
		a.logoutCommand(),
		a.projectCommand(),
		a.pageCommand(),
		a.screenshotCommand(),
		a.annotationCommand(),
		a.commentCommand(),
	)
	return root
}

func (a *app) resolvedConfig() (appconfig.Resolved, error) {
	return appconfig.Resolve(appconfig.Options{
		ConfigPath: a.configPath,
		Flags:      a.flags,
	})
}

func (a *app) client() (*screenote.Client, appconfig.Resolved, error) {
	resolved, err := a.resolvedConfig()
	if err != nil {
		return nil, resolved, err
	}
	if resolved.BaseURL == "" {
		return nil, resolved, usageError("missing_base_url", "base URL is required; set --base-url, SCREENOTE_BASE_URL, or config base_url")
	}
	if resolved.Token == "" {
		token, err := a.storedLoginToken(cmdContext(), resolved)
		if err != nil {
			return nil, resolved, err
		}
		resolved.Token = token
	}

	client, err := screenote.NewClient(resolved.BaseURL, resolved.Token, a.httpClient)
	if err != nil {
		return nil, resolved, usageError("invalid_base_url", err.Error())
	}
	return client, resolved, nil
}

func cmdContext() context.Context {
	return context.Background()
}

func (a *app) storedLoginToken(ctx context.Context, resolved appconfig.Resolved) (string, error) {
	path := defaultConfigPath(a.configPath)
	values, err := appconfig.LoadExpanded(path)
	if err != nil {
		return "", err
	}
	credentials := values.Login
	if credentials == nil || credentials.AccessToken == "" {
		return "", usageError("missing_token", "OAuth bearer token is required; set --token, SCREENOTE_TOKEN, config token, or run screenote login")
	}
	if credentials.BaseURL != "" && resolved.BaseURL != "" && credentials.BaseURL != resolved.BaseURL {
		return "", authError("invalid_token", "stored login credentials are for a different base URL")
	}
	if credentials.ExpiresAt.IsZero() || time.Until(credentials.ExpiresAt) > time.Minute {
		return credentials.AccessToken, nil
	}
	if credentials.RefreshToken == "" {
		return "", authError("invalid_token", "stored OAuth token is expired and has no refresh token")
	}

	metadata, err := screenote.DiscoverOAuth(ctx, resolved.BaseURL, a.httpClient)
	if err != nil {
		return "", authError("invalid_token", "stored OAuth token refresh failed: "+err.Error())
	}
	response, err := screenote.RefreshAccessToken(ctx, metadata, credentials.ClientID, credentials.RefreshToken, a.httpClient)
	if err != nil {
		return "", authError("invalid_token", "stored OAuth token refresh failed: "+err.Error())
	}
	credentials.AccessToken = response.AccessToken
	if response.RefreshToken != "" {
		credentials.RefreshToken = response.RefreshToken
	}
	credentials.ExpiresAt = screenote.ExpiresAt(response, time.Now())
	values.Login = credentials
	if err := appconfig.Save(path, values); err != nil {
		return "", err
	}
	return credentials.AccessToken, nil
}

func (a *app) projectID(_ context.Context, _ *screenote.Client, resolved appconfig.Resolved) (string, error) {
	if resolved.Project != "" {
		return resolved.Project, nil
	}
	return "", usageError("missing_project", "project is required; set --project, SCREENOTE_PROJECT, or config project")
}

func writeJSON(w io.Writer, value any) error {
	return json.NewEncoder(w).Encode(value)
}

func writeRawJSON(w io.Writer, raw json.RawMessage) error {
	if len(raw) == 0 {
		raw = []byte("{}")
	}
	_, err := w.Write(raw)
	if err != nil {
		return err
	}
	if raw[len(raw)-1] != '\n' {
		_, err = io.WriteString(w, "\n")
	}
	return err
}

func intString(id int) string {
	return strconv.Itoa(id)
}

func defaultConfigPath(path string) string {
	if path != "" {
		return path
	}
	return appconfig.DefaultConfigPath
}
