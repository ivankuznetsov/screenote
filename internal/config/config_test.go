package config

import (
	"path/filepath"
	"testing"
)

func TestResolvePrecedence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := Save(path, Values{APIKey: "file-key", BaseURL: "http://file", Project: "file-project"}); err != nil {
		t.Fatal(err)
	}

	resolved, err := Resolve(Options{
		ConfigPath: path,
		Flags:      Values{APIKey: "flag-key"},
		Env: map[string]string{
			"SCREENOTE_API_KEY":  "env-key",
			"SCREENOTE_BASE_URL": "http://env",
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	if resolved.APIKey != "flag-key" || resolved.Sources.APIKey != "flag" {
		t.Fatalf("api key = %q from %q", resolved.APIKey, resolved.Sources.APIKey)
	}
	if resolved.BaseURL != "http://env" || resolved.Sources.BaseURL != "env" {
		t.Fatalf("base url = %q from %q", resolved.BaseURL, resolved.Sources.BaseURL)
	}
	if resolved.Project != "file-project" || resolved.Sources.Project != "config" {
		t.Fatalf("project = %q from %q", resolved.Project, resolved.Sources.Project)
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
