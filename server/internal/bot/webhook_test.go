package bot

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestWebhookChecksTheSecretAndHandlesUpdates(t *testing.T) {
	h := newHarness(t)
	parse := func(body []byte) (Update, bool, error) {
		return Update{ID: string(body), ChatID: "42", Private: true, MessageID: "1", Text: "/help"}, true, nil
	}
	mux := http.NewServeMux()
	mux.Handle("POST /hook/{secret}", Webhook(context.Background(), h.service, parse, WebhookAuth{PathSecret: "s3cret"}, 2))

	wrong := httptest.NewRecorder()
	mux.ServeHTTP(wrong, httptest.NewRequest(http.MethodPost, "/hook/guess", strings.NewReader("1")))
	if wrong.Code != http.StatusNotFound {
		t.Fatalf("wrong secret = %d", wrong.Code)
	}

	ok := httptest.NewRecorder()
	mux.ServeHTTP(ok, httptest.NewRequest(http.MethodPost, "/hook/s3cret", strings.NewReader("1")))
	if ok.Code != http.StatusOK {
		t.Fatalf("right secret = %d", ok.Code)
	}
	deadline := time.Now().Add(2 * time.Second)
	for h.provider.last() != msgHelp {
		if time.Now().After(deadline) {
			t.Fatalf("update not handled; sent %q", h.provider.messages)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestWebhookCanRequireASecretHeader(t *testing.T) {
	h := newHarness(t)
	parse := func(body []byte) (Update, bool, error) {
		return Update{ID: string(body), ChatID: "42", Private: true, MessageID: "1", Text: "/help"}, true, nil
	}
	mux := http.NewServeMux()
	mux.Handle("POST /hook/{secret}", Webhook(context.Background(), h.service, parse, WebhookAuth{
		PathSecret: "s3cret", Header: "X-Telegram-Bot-Api-Secret-Token", HeaderSecret: "s3cret",
	}, 2))

	for name, header := range map[string]string{"missing": "", "wrong": "guess"} {
		request := httptest.NewRequest(http.MethodPost, "/hook/s3cret", strings.NewReader("1"))
		if header != "" {
			request.Header.Set("X-Telegram-Bot-Api-Secret-Token", header)
		}
		response := httptest.NewRecorder()
		mux.ServeHTTP(response, request)
		if response.Code != http.StatusNotFound {
			t.Fatalf("%s header = %d", name, response.Code)
		}
	}

	request := httptest.NewRequest(http.MethodPost, "/hook/s3cret", strings.NewReader("2"))
	request.Header.Set("X-Telegram-Bot-Api-Secret-Token", "s3cret")
	response := httptest.NewRecorder()
	mux.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("right header = %d", response.Code)
	}
}
