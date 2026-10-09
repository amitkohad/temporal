package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

type tokenTransport struct {
	url    string
	client *http.Client
}

func (transport tokenTransport) Do(request *http.Request) (*http.Response, error) {
	clone := request.Clone(request.Context())
	endpoint, err := url.Parse(transport.url)
	if err != nil {
		return nil, err
	}
	clone.URL = endpoint
	return transport.client.Do(clone)
}

func accessToken(expires time.Time) string {
	payload, _ := json.Marshal(map[string]int64{"exp": expires.Unix()})
	return "header." + base64.RawURLEncoding.EncodeToString(payload) + ".signature"
}

func TestToken(t *testing.T) {
	t.Parallel()
	now := time.Unix(1800000000, 0)
	cases := []struct {
		name      string
		status    int
		body      string
		wantError string
	}{
		{"valid", 200, `{"access_token":"` + accessToken(now.Add(time.Hour)) + `","token_type":"Bearer","expires_in":3600}`, ""},
		{"expired", 200, `{"access_token":"` + accessToken(now.Add(time.Minute)) + `","token_type":"Bearer","expires_in":3600}`, "token expires too soon"},
		{"short lifetime", 200, `{"access_token":"` + accessToken(now.Add(time.Hour)) + `","token_type":"Bearer","expires_in":60}`, "token lifetime invalid"},
		{"malformed", 200, `{`, "token response invalid"},
		{"oversized", 200, strings.Repeat("x", maxTokenBytes+1), "token response invalid"},
		{"rejected redacted", 401, `{"secret":"must-not-be-logged"}`, "token exchange rejected"},
		{"redirect", 302, "", "token exchange rejected"},
	}
	for _, item := range cases {
		t.Run(item.name, func(t *testing.T) {
			t.Parallel()
			requests := make(chan bool, 1)
			server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
				valid := request.Method == http.MethodPost && request.Header.Get("Content-Type") == "application/x-www-form-urlencoded"
				valid = request.ParseForm() == nil && valid
				valid = valid && request.Form.Get("scope") == "https://ossrdbms-aad.database.windows.net/.default" && request.Form.Get("client_assertion") == "fresh-assertion"
				requests <- valid
				writer.WriteHeader(item.status)
				_, _ = io.WriteString(writer, item.body)
			}))
			defer server.Close()
			token, err := acquireToken(context.Background(), "11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222", "/token", tokenTransport{server.URL, server.Client()}, func(string) ([]byte, error) { return []byte("fresh-assertion"), nil }, func() time.Time { return now })
			if !<-requests {
				t.Fatal("invalid token exchange fields")
			}
			if item.wantError == "" {
				if err != nil || token != accessToken(now.Add(time.Hour)) {
					t.Fatalf("unexpected result: error=%v", err)
				}
			} else if err == nil || err.Error() != item.wantError || token != "" {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestConfiguration(t *testing.T) {
	t.Parallel()
	_, err := acquireToken(context.Background(), "https://untrusted.example", "invalid", "/token", nil, nil, time.Now)
	if err == nil || err.Error() != "workload identity configuration invalid" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestAssertionReadEveryInvocation(t *testing.T) {
	t.Parallel()
	reads := 0
	read := func(string) ([]byte, error) { reads++; return nil, errors.New("sensitive-path-error") }
	for range 2 {
		_, err := acquireToken(context.Background(), "11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222", "/token", nil, read, time.Now)
		if err == nil || err.Error() != "workload assertion unavailable" {
			t.Fatalf("unexpected error: %v", err)
		}
	}
	if reads != 2 {
		t.Fatalf("got %d reads", reads)
	}
}

func TestClientSelection(t *testing.T) {
	t.Parallel()
	fallback := "11111111-1111-1111-1111-111111111111"
	explicit := "22222222-2222-2222-2222-222222222222"
	cases := []struct {
		name     string
		args     []string
		fallback string
		want     string
	}{
		{"environment default", nil, fallback, fallback},
		{"store override", []string{"--client-id", explicit}, fallback, explicit},
		{"missing value", []string{"--client-id"}, fallback, ""},
		{"invalid UUID", []string{"--client-id", "https://untrusted.example"}, fallback, ""},
		{"unknown flag", []string{"--endpoint", "https://untrusted.example"}, fallback, ""},
		{"unexpected positional", []string{"secret"}, fallback, ""},
		{"missing environment", nil, "", ""},
	}
	for _, item := range cases {
		t.Run(item.name, func(t *testing.T) {
			t.Parallel()
			result, err := parseClientID(item.args, item.fallback)
			if item.want == "" {
				if err == nil || result != "" {
					t.Fatalf("unexpected client selection: %v", err)
				}
			} else if err != nil || result != item.want {
				t.Fatalf("unexpected client selection: %v", err)
			}
		})
	}
}
