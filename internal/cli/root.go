package cli

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strconv"

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
	root.PersistentFlags().StringVar(&a.flags.APIKey, "api-key", "", "Screenote project API key")
	root.PersistentFlags().StringVar(&a.flags.BaseURL, "base-url", "", "Screenote base URL")
	root.PersistentFlags().StringVar(&a.flags.Project, "project", "", "Screenote project ID")
	root.PersistentFlags().StringVar(&a.configPath, "config", "", "Config file path")
	root.PersistentFlags().BoolVar(&a.interactive, "interactive", false, "Allow interactive prompts")

	root.AddCommand(
		a.configCommand(),
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
	if resolved.APIKey == "" {
		return nil, resolved, usageError("missing_api_key", "API key is required; set --api-key, SCREENOTE_API_KEY, or config api_key")
	}

	client, err := screenote.NewClient(resolved.BaseURL, resolved.APIKey, a.httpClient)
	if err != nil {
		return nil, resolved, usageError("invalid_base_url", err.Error())
	}
	return client, resolved, nil
}

func (a *app) projectID(ctx context.Context, client *screenote.Client, resolved appconfig.Resolved) (string, error) {
	if resolved.Project != "" {
		return resolved.Project, nil
	}
	_, projects, err := client.Projects(ctx)
	if err != nil {
		return "", err
	}
	if len(projects.Projects) == 0 {
		return "", usageError("missing_project", "project is required and could not be inferred from the API key")
	}
	return intString(projects.Projects[0].ID), nil
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
