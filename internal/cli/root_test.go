package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestProjectListCommand(t *testing.T) {
	requests := make(chan *http.Request, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests <- r
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"projects":[{"id":1,"name":"Demo"}]}`))
	}))
	defer server.Close()

	stdout, stderr, code := runCLI(t, []string{"--base-url", server.URL, "--api-key", "key", "project", "list"}, "")
	if code != ExitOK {
		t.Fatalf("code=%d stderr=%s", code, stderr)
	}
	if !strings.Contains(stdout, `"projects"`) {
		t.Fatalf("stdout=%s", stdout)
	}
	req := <-requests
	if req.Method != http.MethodGet || req.URL.Path != "/api/v1/projects" {
		t.Fatalf("%s %s", req.Method, req.URL.Path)
	}
	if req.Header.Get("Authorization") != "Bearer key" {
		t.Fatalf("Authorization=%q", req.Header.Get("Authorization"))
	}
}

func TestScreenshotCreateReadsStdin(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/screenshots" {
			t.Fatalf("path=%s", r.URL.Path)
		}
		if err := r.ParseMultipartForm(1024); err != nil {
			t.Fatal(err)
		}
		if r.FormValue("title") != "Home" {
			t.Fatalf("title=%q", r.FormValue("title"))
		}
		file, _, err := r.FormFile("image")
		if err != nil {
			t.Fatal(err)
		}
		defer file.Close()
		_, _ = w.Write([]byte(`{"screenshot_id":3}`))
	}))
	defer server.Close()

	stdout, stderr, code := runCLI(t, []string{"--base-url", server.URL, "--api-key", "key", "screenshot", "create", "--title", "Home"}, "image")
	if code != ExitOK {
		t.Fatalf("code=%d stderr=%s", code, stderr)
	}
	if !strings.Contains(stdout, `"screenshot_id":3`) {
		t.Fatalf("stdout=%s", stdout)
	}
}

func TestPageListInfersProject(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/projects":
			_, _ = w.Write([]byte(`{"projects":[{"id":42,"name":"Demo"}]}`))
		case "/api/v1/projects/42/pages":
			_, _ = w.Write([]byte(`{"pages":[]}`))
		default:
			t.Fatalf("unexpected path %s", r.URL.Path)
		}
	}))
	defer server.Close()

	stdout, stderr, code := runCLI(t, []string{"--base-url", server.URL, "--api-key", "key", "page", "list"}, "")
	if code != ExitOK {
		t.Fatalf("code=%d stderr=%s", code, stderr)
	}
	if !strings.Contains(stdout, `"pages"`) {
		t.Fatalf("stdout=%s", stdout)
	}
}

func TestCommentAddValidatesBody(t *testing.T) {
	stdout, stderr, code := runCLI(t, []string{"--base-url", "http://example.test", "--api-key", "key", "comment", "add", "--annotation", "1"}, "")
	if code != ExitUsage {
		t.Fatalf("code=%d stdout=%s stderr=%s", code, stdout, stderr)
	}
	var payload map[string]string
	if err := json.Unmarshal([]byte(stderr), &payload); err != nil {
		t.Fatal(err)
	}
	if payload["code"] != "missing_body" {
		t.Fatalf("payload=%#v", payload)
	}
}

func TestServerStatusExitCodes(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte(`{"error":"slow down","code":"rate_limited"}`))
	}))
	defer server.Close()

	_, stderr, code := runCLI(t, []string{"--base-url", server.URL, "--api-key", "key", "project", "list"}, "")
	if code != ExitRateLimited {
		t.Fatalf("code=%d stderr=%s", code, stderr)
	}
}

func runCLI(t *testing.T, args []string, stdin string) (string, string, int) {
	t.Helper()
	var out, errOut bytes.Buffer
	cmd := NewTestCommand(context.Background(), strings.NewReader(stdin), &out, &errOut, http.DefaultClient)
	cmd.SetArgs(args)
	if err := cmd.Execute(); err != nil {
		code := writeError(&errOut, err)
		return out.String(), errOut.String(), code
	}
	return out.String(), errOut.String(), ExitOK
}
