package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const maxTokenBytes = 64 * 1024

var identifier = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

type httpDoer interface {
	Do(*http.Request) (*http.Response, error)
}

func readAssertion(path string) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, errors.New("workload assertion unavailable")
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxTokenBytes+1))
	if err != nil || len(data) > maxTokenBytes {
		return nil, errors.New("workload assertion invalid")
	}
	return data, nil
}

func acquireToken(ctx context.Context, tenant, clientID, assertionPath string, client httpDoer, readFile func(string) ([]byte, error), now func() time.Time) (string, error) {
	if !identifier.MatchString(tenant) || !identifier.MatchString(clientID) || assertionPath == "" {
		return "", errors.New("workload identity configuration invalid")
	}
	assertion, err := readFile(assertionPath)
	if err != nil {
		return "", errors.New("workload assertion unavailable")
	}
	assertionText := strings.TrimSpace(string(assertion))
	if len(assertionText) == 0 || len(assertionText) > maxTokenBytes || strings.ContainsAny(assertionText, " \t\r\n") {
		return "", errors.New("workload assertion invalid")
	}
	started := now()
	values := url.Values{
		"client_id":             {clientID},
		"grant_type":            {"client_credentials"},
		"scope":                 {"https://ossrdbms-aad.database.windows.net/.default"},
		"client_assertion_type": {"urn:ietf:params:oauth:client-assertion-type:jwt-bearer"},
		"client_assertion":      {assertionText},
	}
	endpoint := "https://login.microsoftonline.com/" + tenant + "/oauth2/v2.0/token"
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(values.Encode()))
	if err != nil {
		return "", errors.New("token request invalid")
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := client.Do(request)
	if err != nil {
		return "", errors.New("token endpoint unavailable")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", errors.New("token exchange rejected")
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, maxTokenBytes+1))
	if err != nil || len(body) > maxTokenBytes {
		return "", errors.New("token response invalid")
	}
	var result struct {
		AccessToken string          `json:"access_token"`
		TokenType   string          `json:"token_type"`
		ExpiresIn   json.RawMessage `json:"expires_in"`
	}
	if json.Unmarshal(body, &result) != nil || !strings.EqualFold(result.TokenType, "Bearer") || result.AccessToken == "" || strings.ContainsAny(result.AccessToken, " \t\r\n") {
		return "", errors.New("token response invalid")
	}
	seconds, err := strconv.ParseInt(strings.Trim(string(result.ExpiresIn), `"`), 10, 64)
	if err != nil || seconds < 300 || seconds > 86400 {
		return "", errors.New("token lifetime invalid")
	}
	parts := strings.Split(result.AccessToken, ".")
	if len(parts) != 3 {
		return "", errors.New("access token format invalid")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return "", errors.New("access token format invalid")
	}
	var claims struct {
		Expires int64 `json:"exp"`
	}
	if json.Unmarshal(payload, &claims) != nil || claims.Expires <= 0 {
		return "", errors.New("token expiry unavailable")
	}
	expires := started.Add(time.Duration(seconds) * time.Second)
	if tokenExpiry := time.Unix(claims.Expires, 0); tokenExpiry.Before(expires) {
		expires = tokenExpiry
	}
	if expires.Sub(now()) < 5*time.Minute {
		return "", errors.New("token expires too soon")
	}
	return result.AccessToken, nil
}

func parseClientID(args []string, fallback string) (string, error) {
	flags := flag.NewFlagSet("entra-token", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	selected := flags.String("client-id", fallback, "Managed identity application client UUID")
	if flags.Parse(args) != nil || flags.NArg() != 0 || !identifier.MatchString(*selected) {
		return "", errors.New("client identity selection invalid")
	}
	return *selected, nil
}

func main() {
	clientID, err := parseClientID(os.Args[1:], os.Getenv("AZURE_CLIENT_ID"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "PostgreSQL token acquisition failed: "+err.Error())
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	client := &http.Client{Timeout: 15 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
	token, err := acquireToken(ctx, os.Getenv("AZURE_TENANT_ID"), clientID, os.Getenv("AZURE_FEDERATED_TOKEN_FILE"), client, readAssertion, time.Now)
	if err != nil {
		fmt.Fprintln(os.Stderr, "PostgreSQL token acquisition failed: "+err.Error())
		os.Exit(1)
	}
	fmt.Println(token)
}
