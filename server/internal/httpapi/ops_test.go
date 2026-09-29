package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/mhdolatabadi/nafir/server/internal/bot"
)

type fakeHealth []bot.BotHealth

func (f fakeHealth) Health(context.Context) ([]bot.BotHealth, error) { return f, nil }

func TestOpsBotsNeedsTheOperatorToken(t *testing.T) {
	token := strings.Repeat("o", 32)
	handler := NewHandler(Config{Ops: NewOpsHandlers(token, fakeHealth{
		{Provider: "bale", Problems: []string{}},
		{Provider: "telegram", Problems: []string{"webhook not registered"}},
	})})

	for name, header := range map[string]string{"none": "", "wrong": "Bearer " + strings.Repeat("x", 32)} {
		request := httptest.NewRequest(http.MethodGet, "/api/v1/ops/bots", nil)
		if header != "" {
			request.Header.Set("Authorization", header)
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != http.StatusNotFound {
			t.Fatalf("%s token = %d", name, response.Code)
		}
	}

	request := httptest.NewRequest(http.MethodGet, "/api/v1/ops/bots", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	var body botHealthResponse
	json.NewDecoder(response.Body).Decode(&body)
	if response.Code != http.StatusOK || body.Healthy || len(body.Bots) != 2 {
		t.Fatalf("ops = %d %+v", response.Code, body)
	}
}

func TestOpsIsNotServedWithoutAToken(t *testing.T) {
	response := httptest.NewRecorder()
	NewHandler(Config{}).ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/ops/bots", nil))
	if response.Code != http.StatusNotFound {
		t.Fatalf("ops without config = %d", response.Code)
	}
}
