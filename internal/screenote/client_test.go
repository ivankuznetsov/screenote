package screenote

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestClientSendsAuthAndParsesErrors(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-key" {
			t.Fatalf("Authorization = %q", r.Header.Get("Authorization"))
		}
		http.Error(w, `{"error":"nope","code":"unauthorized"}`, http.StatusUnauthorized)
	}))
	defer server.Close()

	client, err := NewClient(server.URL, "test-key", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = client.Projects(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	apiErr, ok := err.(*Error)
	if !ok {
		t.Fatalf("err = %T", err)
	}
	if apiErr.StatusCode != http.StatusUnauthorized || apiErr.Code != "unauthorized" {
		t.Fatalf("apiErr = %#v", apiErr)
	}
}

func TestClientCreateScreenshotMultipart(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/api/v1/screenshots" {
			t.Fatalf("%s %s", r.Method, r.URL.Path)
		}
		if err := r.ParseMultipartForm(1024); err != nil {
			t.Fatal(err)
		}
		if got := r.FormValue("title"); got != "Home" {
			t.Fatalf("title = %q", got)
		}
		file, header, err := r.FormFile("image")
		if err != nil {
			t.Fatal(err)
		}
		defer file.Close()
		data, _ := io.ReadAll(file)
		if header.Filename != "stdin.png" || string(data) != "png-data" {
			t.Fatalf("file %q %q", header.Filename, string(data))
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"screenshot_id": 7})
	}))
	defer server.Close()

	client, err := NewClient(server.URL, "test-key", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	raw, err := client.CreateScreenshot(context.Background(), "Home", "", "stdin.png", "image/png", strings.NewReader("png-data"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `"screenshot_id":7`) {
		t.Fatalf("raw = %s", raw)
	}
}
