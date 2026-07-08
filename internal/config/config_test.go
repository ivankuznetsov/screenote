package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolvePrecedence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := Save(path, Values{Token: "file-token", BaseURL: "http://file", Project: "file-project"}); err != nil {
		t.Fatal(err)
	}

	resolved, err := Resolve(Options{
		ConfigPath: path,
		Flags:      Values{Token: "flag-token"},
		Env: map[string]string{
			"SCREENOTE_TOKEN":    "env-token",
			"SCREENOTE_BASE_URL": "http://env",
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	if resolved.Token != "flag-token" || resolved.Sources.Token != "flag" {
		t.Fatalf("token = %q from %q", resolved.Token, resolved.Sources.Token)
	}
	if resolved.BaseURL != "http://env" || resolved.Sources.BaseURL != "env" {
		t.Fatalf("base url = %q from %q", resolved.BaseURL, resolved.Sources.BaseURL)
	}
	if resolved.Project != "file-project" || resolved.Sources.Project != "config" {
		t.Fatalf("project = %q from %q", resolved.Project, resolved.Sources.Project)
	}
}

func TestResolveTokenSources(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := Save(path, Values{Token: "file-token"}); err != nil {
		t.Fatal(err)
	}

	envResolved, err := Resolve(Options{
		ConfigPath: path,
		Env:        map[string]string{"SCREENOTE_TOKEN": "env-token"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if envResolved.Token != "env-token" || envResolved.Sources.Token != "env" {
		t.Fatalf("token = %q from %q", envResolved.Token, envResolved.Sources.Token)
	}

	fileResolved, err := Resolve(Options{ConfigPath: path})
	if err != nil {
		t.Fatal(err)
	}
	if fileResolved.Token != "file-token" || fileResolved.Sources.Token != "config" {
		t.Fatalf("token = %q from %q", fileResolved.Token, fileResolved.Sources.Token)
	}
}

func TestResolveIgnoresLegacyAPIKeySources(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte("api_key = \"legacy\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	resolved, err := Resolve(Options{
		ConfigPath: path,
		Env:        map[string]string{"SCREENOTE_API_KEY": "legacy-env"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if resolved.Token != "" || resolved.Sources.Token != "" {
		t.Fatalf("legacy API key source resolved token: %#v", resolved)
	}
}

func TestLoadMissingConfig(t *testing.T) {
	values, err := Load(filepath.Join(t.TempDir(), "missing.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if values != (Values{}) {
		t.Fatalf("values = %#v", values)
	}
}
