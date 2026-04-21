package server

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"mime"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	headerAdvancedReaderClientID               = "X-Advanced-Reader-Client-Id"
	headerAdvancedReaderTimestamp              = "X-Advanced-Reader-Timestamp"
	headerAdvancedReaderNonce                  = "X-Advanced-Reader-Nonce"
	headerAdvancedReaderSignature              = "X-Advanced-Reader-Signature"
	headerAdvancedReaderSignatureVersion       = "X-Advanced-Reader-Signature-Version"
	headerCatsRequesterUID                     = "X-Cats-Requester-Uid"
	signatureVersionV1                         = "v1"
	defaultReaderAnalyzePath                   = "/analyze"
	defaultReaderProxyTimeout                  = 300 * time.Second
	defaultReaderProxyMaxBodyBytes       int64 = 100 << 20 // 100 MB
)

// ReaderProxyOptions configures the Cats-to-advanced-reader proxy.
type ReaderProxyOptions struct {
	Timeout      time.Duration
	MaxBodyBytes int64
	ClientID     string
	ClientSecret string
	SigningPath  string
}

// ReaderProxyHandler proxies authenticated Cats requests to the internal advanced-reader service.
type ReaderProxyHandler struct {
	analyzeURL   string
	signingPath  string
	client       *http.Client
	maxBodyBytes int64
	clientID     string
	clientSecret string
	configError  error
}

// NewReaderProxyHandler builds a proxy handler for the given advanced-reader base URL.
func NewReaderProxyHandler(baseURL string, opts ReaderProxyOptions) *ReaderProxyHandler {
	handler := &ReaderProxyHandler{
		maxBodyBytes: opts.MaxBodyBytes,
		clientID:     strings.TrimSpace(opts.ClientID),
		clientSecret: strings.TrimSpace(opts.ClientSecret),
	}

	if handler.maxBodyBytes <= 0 {
		handler.maxBodyBytes = defaultReaderProxyMaxBodyBytes
	}

	timeout := opts.Timeout
	if timeout <= 0 {
		timeout = defaultReaderProxyTimeout
	}
	handler.client = &http.Client{Timeout: timeout}

	trimmedBaseURL := strings.TrimSpace(baseURL)
	if trimmedBaseURL == "" {
		handler.configError = errors.New("ADVANCED_READER_INTERNAL_URL is not set")
		return handler
	}

	parsedBaseURL, err := url.Parse(trimmedBaseURL)
	if err != nil || parsedBaseURL.Scheme == "" || parsedBaseURL.Host == "" {
		handler.configError = fmt.Errorf("invalid ADVANCED_READER_INTERNAL_URL: %q", trimmedBaseURL)
		return handler
	}

	analyzeURL := *parsedBaseURL
	analyzeURL.Path = joinURLPath(parsedBaseURL.Path, defaultReaderAnalyzePath)
	analyzeURL.RawPath = ""
	analyzeURL.RawQuery = ""
	analyzeURL.Fragment = ""
	handler.analyzeURL = analyzeURL.String()

	handler.signingPath = strings.TrimSpace(opts.SigningPath)
	if handler.signingPath == "" {
		handler.signingPath = analyzeURL.Path
	}
	if !strings.HasPrefix(handler.signingPath, "/") {
		handler.signingPath = "/" + handler.signingPath
	}

	hasClientID := handler.clientID != ""
	hasClientSecret := handler.clientSecret != ""
	if hasClientID != hasClientSecret {
		handler.configError = errors.New(
			"advanced-reader proxy signing requires both ADVANCED_READER_CLIENT_ID and ADVANCED_READER_CLIENT_SECRET",
		)
	}

	return handler
}

// NewReaderProxyHandlerFromEnv builds a proxy handler from Cats service env vars.
func NewReaderProxyHandlerFromEnv() *ReaderProxyHandler {
	timeoutSeconds, err := parsePositiveInt64Env("ADVANCED_READER_INTERNAL_TIMEOUT_SECONDS", int64(defaultReaderProxyTimeout/time.Second))
	if err != nil {
		return &ReaderProxyHandler{configError: err}
	}

	maxBodyBytes, err := parsePositiveInt64Env("ADVANCED_READER_PROXY_MAX_BODY_BYTES", defaultReaderProxyMaxBodyBytes)
	if err != nil {
		return &ReaderProxyHandler{configError: err}
	}

	clientSecret, err := readAdvancedReaderClientSecretFromEnv()
	if err != nil {
		return &ReaderProxyHandler{configError: err}
	}

	return NewReaderProxyHandler(
		os.Getenv("ADVANCED_READER_INTERNAL_URL"),
		ReaderProxyOptions{
			Timeout:      time.Duration(timeoutSeconds) * time.Second,
			MaxBodyBytes: maxBodyBytes,
			ClientID:     os.Getenv("ADVANCED_READER_CLIENT_ID"),
			ClientSecret: clientSecret,
			SigningPath:  os.Getenv("ADVANCED_READER_SIGNING_PATH"),
		},
	)
}

// ConfigError returns the startup or configuration error, if any.
func (h *ReaderProxyHandler) ConfigError() error {
	return h.configError
}

// HandleAnalyze handles POST /api/reader/analyze and forwards the raw multipart request upstream.
func (h *ReaderProxyHandler) HandleAnalyze(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	if h.configError != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": h.configError.Error()})
		return
	}

	contentType := strings.TrimSpace(r.Header.Get("Content-Type"))
	mediaType, _, err := mime.ParseMediaType(contentType)
	if err != nil || mediaType != "multipart/form-data" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Content-Type must be multipart/form-data"})
		return
	}

	requesterUID := UIDFromContext(r.Context())
	r.Body = http.MaxBytesReader(w, r.Body, h.maxBodyBytes)

	tempFile, err := os.CreateTemp("", "cats-reader-proxy-*")
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to buffer request"})
		return
	}
	defer func() {
		tempFile.Close()
		os.Remove(tempFile.Name())
	}()

	hasher := sha256.New()
	written, err := io.Copy(io.MultiWriter(tempFile, hasher), r.Body)
	if err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			writeJSON(w, http.StatusRequestEntityTooLarge, map[string]string{"error": "reader request body is too large"})
			return
		}
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "failed to read reader request body"})
		return
	}

	if _, err := tempFile.Seek(0, io.SeekStart); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to prepare upstream reader request"})
		return
	}

	upstreamReq, err := http.NewRequestWithContext(r.Context(), http.MethodPost, h.analyzeURL, tempFile)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to build upstream reader request"})
		return
	}

	upstreamReq.ContentLength = written
	upstreamReq.Header.Set("Content-Type", contentType)
	upstreamReq.Header.Set("Accept", "application/json")
	upstreamReq.Header.Set("User-Agent", "cats-company-reader-proxy/1.0")
	if requesterUID != 0 {
		upstreamReq.Header.Set(headerCatsRequesterUID, strconv.FormatInt(requesterUID, 10))
	}

	if err := h.applySigningHeaders(upstreamReq.Header, hex.EncodeToString(hasher.Sum(nil))); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": err.Error()})
		return
	}

	resp, err := h.client.Do(upstreamReq)
	if err != nil {
		log.Printf("[reader-proxy] upstream request failed for uid=%d: %v", requesterUID, err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "reader upstream request failed"})
		return
	}
	defer resp.Body.Close()

	if responseContentType := strings.TrimSpace(resp.Header.Get("Content-Type")); responseContentType != "" {
		w.Header().Set("Content-Type", responseContentType)
	}
	w.WriteHeader(resp.StatusCode)

	if _, err := io.Copy(w, resp.Body); err != nil {
		log.Printf("[reader-proxy] response copy failed for uid=%d: %v", requesterUID, err)
	}
}

func (h *ReaderProxyHandler) applySigningHeaders(headers http.Header, bodyHash string) error {
	if h.clientID == "" && h.clientSecret == "" {
		return nil
	}
	if h.clientID == "" || h.clientSecret == "" {
		return errors.New("advanced-reader proxy signing is misconfigured")
	}

	timestamp := strconv.FormatInt(time.Now().Unix(), 10)
	nonce, err := randomHex(16)
	if err != nil {
		return fmt.Errorf("failed to build advanced-reader nonce: %w", err)
	}

	canonical := strings.Join([]string{
		http.MethodPost,
		h.signingPath,
		timestamp,
		nonce,
		bodyHash,
	}, "\n")
	mac := hmac.New(sha256.New, []byte(h.clientSecret))
	mac.Write([]byte(canonical))
	signature := hex.EncodeToString(mac.Sum(nil))

	headers.Set(headerAdvancedReaderClientID, h.clientID)
	headers.Set(headerAdvancedReaderTimestamp, timestamp)
	headers.Set(headerAdvancedReaderNonce, nonce)
	headers.Set(headerAdvancedReaderSignature, signature)
	headers.Set(headerAdvancedReaderSignatureVersion, signatureVersionV1)
	return nil
}

func readAdvancedReaderClientSecretFromEnv() (string, error) {
	secretFile := strings.TrimSpace(os.Getenv("ADVANCED_READER_CLIENT_SECRET_FILE"))
	if secretFile != "" {
		contents, err := os.ReadFile(secretFile)
		if err != nil {
			return "", fmt.Errorf("failed to read ADVANCED_READER_CLIENT_SECRET_FILE: %w", err)
		}
		return strings.TrimSpace(string(contents)), nil
	}
	return strings.TrimSpace(os.Getenv("ADVANCED_READER_CLIENT_SECRET")), nil
}

func parsePositiveInt64Env(name string, defaultValue int64) (int64, error) {
	rawValue := strings.TrimSpace(os.Getenv(name))
	if rawValue == "" {
		return defaultValue, nil
	}

	parsedValue, err := strconv.ParseInt(rawValue, 10, 64)
	if err != nil || parsedValue <= 0 {
		return 0, fmt.Errorf("%s must be a positive integer", name)
	}
	return parsedValue, nil
}

func joinURLPath(basePath, suffix string) string {
	trimmedBasePath := strings.TrimRight(basePath, "/")
	if trimmedBasePath == "" {
		return suffix
	}
	return trimmedBasePath + suffix
}

func randomHex(size int) (string, error) {
	buffer := make([]byte, size)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	return hex.EncodeToString(buffer), nil
}
