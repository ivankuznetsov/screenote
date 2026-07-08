package cli

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestScreenshotListSendsFilters(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/projects/7/screenshots" {
			t.Fatalf("path=%s", r.URL.Path)
		}
		if r.URL.Query().Get("page_id") != "9" || r.URL.Query().Get("status") != "ready" {
			t.Fatalf("query=%s", r.URL.RawQuery)
		}
		_, _ = w.Write([]byte(`{"screenshots":[],"pagination":{"total":0,"limit":10,"offset":2}}`))
	}))
	defer server.Close()

	stdout, stderr, code := runCLI(t, []string{"--base-url", server.URL, "--api-key", "key", "--project", "7", "screenshot", "list", "--page", "9", "--status", "ready", "--limit", "10", "--offset", "2"}, "")
	if code != ExitOK {
		t.Fatalf("code=%d stderr=%s", code, stderr)
	}
	if !strings.Contains(stdout, `"screenshots"`) {
		t.Fatalf("stdout=%s", stdout)
	}
}

func TestAnnotationGetPath(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/api/v1/annotations/5" {
			t.Fatalf("%s %s", r.Method, r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"id":5}`))
	}))
	defer server.Close()

	stdout, stderr, code := runCLI(t, []string{"--base-url", server.URL, "--api-key", "key", "annotation", "get", "--annotation", "5"}, "")
	if code != ExitOK {
		t.Fatalf("code=%d stderr=%s", code, stderr)
	}
	if !strings.Contains(stdout, `"id":5`) {
		t.Fatalf("stdout=%s", stdout)
	}
}

func TestAnnotationListPath(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/api/v1/screenshots/4/annotations" {
			t.Fatalf("%s %s", r.Method, r.URL.Path)
		}
		if r.URL.Query().Get("status") != "open" || r.URL.Query().Get("viewport") != "mobile" {
			t.Fatalf("query=%s", r.URL.RawQuery)
		}
		_, _ = w.Write([]byte(`{"annotations":[]}`))
	}))
	defer server.Close()

	_, stderr, code := runCLI(t, []string{"--base-url", server.URL, "--api-key", "key", "annotation", "list", "--screenshot", "4", "--status", "open", "--viewport", "mobile"}, "")
	if code != ExitOK {
		t.Fatalf("code=%d stderr=%s", code, stderr)
	}
}

func TestCommentAddPathAndBody(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/api/v1/annotations/5/comments" {
			t.Fatalf("%s %s", r.Method, r.URL.Path)
		}
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		if r.Form.Get("body") != "hello" {
			t.Fatalf("body=%q", r.Form.Get("body"))
		}
		_, _ = w.Write([]byte(`{"success":true}`))
	}))
	defer server.Close()

	_, stderr, code := runCLI(t, []string{"--base-url", server.URL, "--api-key", "key", "comment", "add", "--annotation", "5", "--body", "hello"}, "")
	if code != ExitOK {
		t.Fatalf("code=%d stderr=%s", code, stderr)
	}
}
