package config

import (
	"errors"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

const DefaultConfigPath = "~/.config/screenote/config.toml"

type Values struct {
	APIKey  string `toml:"api_key" json:"api_key,omitempty"`
	BaseURL string `toml:"base_url" json:"base_url,omitempty"`
	Project string `toml:"project" json:"project,omitempty"`
}

type Sources struct {
	APIKey  string `json:"api_key,omitempty"`
	BaseURL string `json:"base_url,omitempty"`
	Project string `json:"project,omitempty"`
}

type Resolved struct {
	Values
	Sources Sources `json:"sources"`
}

type Options struct {
	ConfigPath string
	Flags      Values
	Env        map[string]string
}

func Resolve(options Options) (Resolved, error) {
	env := func(key string) string { return os.Getenv(key) }
	if options.Env != nil {
		env = func(key string) string { return options.Env[key] }
	}

	path, err := ExpandPath(options.ConfigPath)
	if err != nil {
		return Resolved{}, err
	}
	if path == "" {
		path, err = ExpandPath(DefaultConfigPath)
		if err != nil {
			return Resolved{}, err
		}
	}

	fileValues, err := Load(path)
	if err != nil {
		return Resolved{}, err
	}

	resolved := Resolved{Values: fileValues}
	if fileValues.APIKey != "" {
		resolved.Sources.APIKey = "config"
	}
	if fileValues.BaseURL != "" {
		resolved.Sources.BaseURL = "config"
	}
	if fileValues.Project != "" {
		resolved.Sources.Project = "config"
	}

	apply := func(value, source string, target *string, sourceTarget *string) {
		if value == "" {
			return
		}
		*target = value
		*sourceTarget = source
	}

	apply(env("SCREENOTE_API_KEY"), "env", &resolved.APIKey, &resolved.Sources.APIKey)
	apply(env("SCREENOTE_BASE_URL"), "env", &resolved.BaseURL, &resolved.Sources.BaseURL)
	apply(env("SCREENOTE_PROJECT"), "env", &resolved.Project, &resolved.Sources.Project)
	apply(options.Flags.APIKey, "flag", &resolved.APIKey, &resolved.Sources.APIKey)
	apply(options.Flags.BaseURL, "flag", &resolved.BaseURL, &resolved.Sources.BaseURL)
	apply(options.Flags.Project, "flag", &resolved.Project, &resolved.Sources.Project)

	return resolved, nil
}

func Load(path string) (Values, error) {
	if path == "" {
		return Values{}, nil
	}

	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return Values{}, nil
	}
	if err != nil {
		return Values{}, err
	}

	var values Values
	if _, err := toml.Decode(string(data), &values); err != nil {
		return Values{}, err
	}
	return values, nil
}

func LoadExpanded(path string) (Values, error) {
	expanded, err := ExpandPath(path)
	if err != nil {
		return Values{}, err
	}
	return Load(expanded)
}

func Save(path string, values Values) error {
	expanded, err := ExpandPath(path)
	if err != nil {
		return err
	}
	if expanded == "" {
		expanded, err = ExpandPath(DefaultConfigPath)
		if err != nil {
			return err
		}
	}
	if err := os.MkdirAll(filepath.Dir(expanded), 0o700); err != nil {
		return err
	}

	f, err := os.OpenFile(expanded, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()

	return toml.NewEncoder(f).Encode(values)
}

func ExpandPath(path string) (string, error) {
	if path == "" || path[0] != '~' {
		return path, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	if path == "~" {
		return home, nil
	}
	if len(path) > 1 && os.IsPathSeparator(path[1]) {
		return filepath.Join(home, path[2:]), nil
	}
	return "", errors.New("unsupported config path")
}
