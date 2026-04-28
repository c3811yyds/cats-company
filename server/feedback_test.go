package server

import "testing"

func TestAbsoluteFeedbackURL(t *testing.T) {
	t.Setenv("FEEDBACK_PUBLIC_BASE_URL", "https://app.catsco.cc/")

	got := absoluteFeedbackURL("/uploads/feedback/example.png", "https://ignored.example/chat")
	want := "https://app.catsco.cc/uploads/feedback/example.png"
	if got != want {
		t.Fatalf("absoluteFeedbackURL() = %q, want %q", got, want)
	}
}

func TestAbsoluteFeedbackURLFallsBackToPageOrigin(t *testing.T) {
	got := absoluteFeedbackURL("/uploads/feedback/example.png", "https://app.catsco.cc/chats")
	want := "https://app.catsco.cc/uploads/feedback/example.png"
	if got != want {
		t.Fatalf("absoluteFeedbackURL() = %q, want %q", got, want)
	}
}

func TestAbsoluteFeedbackURLKeepsAbsoluteURL(t *testing.T) {
	got := absoluteFeedbackURL("https://cdn.example.com/example.png", "https://app.catsco.cc/chats")
	want := "https://cdn.example.com/example.png"
	if got != want {
		t.Fatalf("absoluteFeedbackURL() = %q, want %q", got, want)
	}
}
