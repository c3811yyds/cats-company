package server

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestHandleServeFileAllowsGeneratedFeedbackImage(t *testing.T) {
	dir := t.TempDir()
	fileName := "20260428_0123456789abcdef0123456789abcdef.png"
	fullPath := filepath.Join(dir, "feedback", fileName)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(fullPath, []byte("fake image"), 0644); err != nil {
		t.Fatal(err)
	}

	handler := NewUploadHandler(dir, "/uploads")
	req := httptest.NewRequest(http.MethodGet, "/uploads/feedback/"+fileName, nil)
	rec := httptest.NewRecorder()

	handler.HandleServeFile(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options = %q, want nosniff", got)
	}
}

func TestHandleServeFileRejectsUnexpectedDirectory(t *testing.T) {
	handler := NewUploadHandler(t.TempDir(), "/uploads")
	req := httptest.NewRequest(http.MethodGet, "/uploads/secrets/20260428_0123456789abcdef0123456789abcdef.png", nil)
	rec := httptest.NewRecorder()

	handler.HandleServeFile(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}

func TestHandleServeFileRejectsNonGeneratedName(t *testing.T) {
	handler := NewUploadHandler(t.TempDir(), "/uploads")
	req := httptest.NewRequest(http.MethodGet, "/uploads/feedback/manual.png", nil)
	rec := httptest.NewRecorder()

	handler.HandleServeFile(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}

func TestHandleServeFileRejectsMutationMethods(t *testing.T) {
	handler := NewUploadHandler(t.TempDir(), "/uploads")
	req := httptest.NewRequest(http.MethodPost, "/uploads/feedback/20260428_0123456789abcdef0123456789abcdef.png", nil)
	rec := httptest.NewRecorder()

	handler.HandleServeFile(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
	}
}
