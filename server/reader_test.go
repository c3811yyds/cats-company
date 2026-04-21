package server

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestReaderProxyHandlerHandleAnalyzeForwardsMultipartAndSigns(t *testing.T) {
	var upstreamBody []byte
	var upstreamMethod string
	var upstreamPath string
	var upstreamContentType string
	var upstreamClientID string
	var upstreamTimestamp string
	var upstreamNonce string
	var upstreamSignature string
	var upstreamVersion string
	var upstreamRequesterUID string

	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamMethod = r.Method
		upstreamPath = r.URL.Path
		upstreamContentType = r.Header.Get("Content-Type")
		upstreamClientID = r.Header.Get(headerAdvancedReaderClientID)
		upstreamTimestamp = r.Header.Get(headerAdvancedReaderTimestamp)
		upstreamNonce = r.Header.Get(headerAdvancedReaderNonce)
		upstreamSignature = r.Header.Get(headerAdvancedReaderSignature)
		upstreamVersion = r.Header.Get(headerAdvancedReaderSignatureVersion)
		upstreamRequesterUID = r.Header.Get(headerCatsRequesterUID)

		var err error
		upstreamBody, err = io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("failed to read upstream body: %v", err)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"analysis":"ok"}`))
	}))
	defer upstream.Close()

	handler := NewReaderProxyHandler(upstream.URL, ReaderProxyOptions{
		Timeout:      5 * time.Second,
		MaxBodyBytes: 1 << 20,
		ClientID:     "cats-reader",
		ClientSecret: "top-secret",
	})

	requestBody, contentType := buildReaderMultipartRequest(t, map[string]string{
		"prompt":       "Extract visible text",
		"page_limit":   "2",
		"force_vision": "true",
	}, "diagram.png", []byte("fake-image"))

	req := httptest.NewRequest(http.MethodPost, "/api/reader/analyze", bytes.NewReader(requestBody))
	req.Header.Set("Content-Type", contentType)
	req = req.WithContext(context.WithValue(req.Context(), uidKey, int64(42)))
	rr := httptest.NewRecorder()

	handler.HandleAnalyze(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}

	if got := strings.TrimSpace(rr.Body.String()); got != `{"analysis":"ok"}` {
		t.Fatalf("unexpected response body: %q", got)
	}

	if upstreamMethod != http.MethodPost {
		t.Fatalf("expected POST upstream, got %s", upstreamMethod)
	}
	if upstreamPath != "/analyze" {
		t.Fatalf("expected /analyze upstream path, got %s", upstreamPath)
	}
	if !strings.Contains(upstreamContentType, "multipart/form-data") {
		t.Fatalf("expected multipart content type, got %q", upstreamContentType)
	}
	if !bytes.Contains(upstreamBody, []byte(`name="prompt"`)) {
		t.Fatalf("expected prompt field in upstream multipart body")
	}
	if !bytes.Contains(upstreamBody, []byte("Extract visible text")) {
		t.Fatalf("expected prompt value in upstream multipart body")
	}
	if upstreamClientID != "cats-reader" {
		t.Fatalf("expected upstream client id to be forwarded")
	}
	if upstreamVersion != signatureVersionV1 {
		t.Fatalf("expected signature version %q, got %q", signatureVersionV1, upstreamVersion)
	}
	if upstreamRequesterUID != "42" {
		t.Fatalf("expected requester uid header, got %q", upstreamRequesterUID)
	}

	bodyHash := sha256.Sum256(upstreamBody)
	expectedSignature := buildExpectedSignature("top-secret", "/analyze", upstreamTimestamp, upstreamNonce, hex.EncodeToString(bodyHash[:]))
	if upstreamSignature != expectedSignature {
		t.Fatalf("unexpected signature: got %q want %q", upstreamSignature, expectedSignature)
	}
}

func TestReaderProxyHandlerHandleAnalyzeReturnsUnavailableWhenMisconfigured(t *testing.T) {
	handler := &ReaderProxyHandler{configError: io.EOF}

	requestBody, contentType := buildReaderMultipartRequest(t, map[string]string{"prompt": "test"}, "test.png", []byte("img"))
	req := httptest.NewRequest(http.MethodPost, "/api/reader/analyze", bytes.NewReader(requestBody))
	req.Header.Set("Content-Type", contentType)
	rr := httptest.NewRecorder()

	handler.HandleAnalyze(rr, req)

	if rr.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", rr.Code)
	}
	if !strings.Contains(rr.Body.String(), "EOF") {
		t.Fatalf("expected config error in response, got %q", rr.Body.String())
	}
}

func buildReaderMultipartRequest(t *testing.T, fields map[string]string, fileName string, fileContents []byte) ([]byte, string) {
	t.Helper()

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)

	for key, value := range fields {
		if err := writer.WriteField(key, value); err != nil {
			t.Fatalf("failed to write field %s: %v", key, err)
		}
	}

	part, err := writer.CreateFormFile("file", fileName)
	if err != nil {
		t.Fatalf("failed to create file field: %v", err)
	}
	if _, err := part.Write(fileContents); err != nil {
		t.Fatalf("failed to write file contents: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("failed to close multipart writer: %v", err)
	}

	return body.Bytes(), writer.FormDataContentType()
}

func buildExpectedSignature(secret, signingPath, timestamp, nonce, bodyHash string) string {
	canonical := strings.Join([]string{
		http.MethodPost,
		signingPath,
		timestamp,
		nonce,
		bodyHash,
	}, "\n")
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(canonical))
	return hex.EncodeToString(mac.Sum(nil))
}
