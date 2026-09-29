package botapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/mhdolatabadi/nafir/server/internal/bot"
)

const token = "123456:secret-token"

// A private-chat audio message in the Telegram/Bale update format.
const audioUpdate = `{
  "update_id": 5001,
  "message": {
    "message_id": 77,
    "from": {"id": 9007199254740993, "is_bot": false, "first_name": "علی"},
    "chat": {"id": 9007199254740993, "type": "private"},
    "date": 1759150000,
    "audio": {
      "file_id": "AgADBAAD", "file_unique_id": "u1", "duration": 215,
      "performer": "خواننده", "title": "آهنگ", "file_name": "song.mp3",
      "mime_type": "audio/mpeg", "file_size": 5242880
    }
  }
}`

func TestParseAudioMessage(t *testing.T) {
	u, ok, err := Parse([]byte(audioUpdate))
	if err != nil || !ok {
		t.Fatalf("Parse = %v, %v", ok, err)
	}
	// Chat IDs beyond float64 precision must survive intact.
	if u.ID != "5001" || u.ChatID != "9007199254740993" || !u.Private || u.MessageID != "77" {
		t.Fatalf("update = %+v", u)
	}
	want := bot.File{ID: "AgADBAAD", Name: "song.mp3", MIMEType: "audio/mpeg", SizeBytes: 5242880, Title: "آهنگ", Performer: "خواننده"}
	if u.File == nil || *u.File != want {
		t.Fatalf("file = %+v", u.File)
	}
}

func TestParseDocumentTextGroupAndOtherUpdates(t *testing.T) {
	u, ok, _ := Parse([]byte(`{"update_id":1,"message":{"message_id":2,"chat":{"id":3,"type":"private"},
		"document":{"file_id":"d","file_name":"a.flac","mime_type":"audio/flac","file_size":10}}}`))
	if !ok || u.File == nil || u.File.Name != "a.flac" {
		t.Fatalf("document = %+v", u)
	}
	u, ok, _ = Parse([]byte(`{"update_id":1,"message":{"message_id":2,"chat":{"id":-100,"type":"group"},"text":"/start"}}`))
	if !ok || u.Private || u.Text != "/start" || u.File != nil {
		t.Fatalf("group text = %+v", u)
	}
	if _, ok, err := Parse([]byte(`{"update_id":1,"edited_message":{"message_id":2}}`)); ok || err != nil {
		t.Fatalf("edited message: ok=%v err=%v", ok, err)
	}
	if _, _, err := Parse([]byte(`{"message":{}}`)); err == nil {
		t.Fatal("update without ID accepted")
	}
	if _, _, err := Parse([]byte(`not json`)); err == nil {
		t.Fatal("invalid JSON accepted")
	}
}

func newTestClient(t *testing.T, handler http.HandlerFunc) *Client {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	client, err := New(Config{Name: "bale", BaseURL: server.URL + "/", Token: token, MaxDownloadBytes: 20 << 20})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func TestSendMessageAndDownloadFile(t *testing.T) {
	var sent map[string]any
	client := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/bot" + token + "/sendMessage":
			json.NewDecoder(r.Body).Decode(&sent)
			io.WriteString(w, `{"ok":true,"result":{}}`)
		case "/bot" + token + "/getFile":
			io.WriteString(w, `{"ok":true,"result":{"file_id":"f","file_path":"music/f.mp3","file_size":5}}`)
		case "/file/bot" + token + "/music/f.mp3":
			io.WriteString(w, "ID3xy")
		default:
			http.NotFound(w, r)
		}
	})

	if err := client.Send(context.Background(), "9007199254740993", "سلام"); err != nil {
		t.Fatal(err)
	}
	if sent["text"] != "سلام" || sent["chat_id"] != 9007199254740993.0 {
		t.Fatalf("sent %v", sent)
	}

	body, size, err := client.Open(context.Background(), "f")
	if err != nil {
		t.Fatal(err)
	}
	defer body.Close()
	data, _ := io.ReadAll(body)
	if size != 5 || string(data) != "ID3xy" {
		t.Fatalf("download = %d %q", size, data)
	}
}

func TestDownloadSizeComesFromTheResponseNotGetFile(t *testing.T) {
	client := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/bot" + token + "/getFile":
			// Bale reported 85 here for a 17 MB file.
			io.WriteString(w, `{"ok":true,"result":{"file_id":"f","file_path":"music/f.mp3","file_size":85}}`)
		case "/file/bot" + token + "/music/f.mp3":
			w.Header().Set("Content-Length", "5")
			io.WriteString(w, "ID3xy")
		default:
			http.NotFound(w, r)
		}
	})

	body, size, err := client.Open(context.Background(), "f")
	if err != nil {
		t.Fatal(err)
	}
	defer body.Close()
	data, _ := io.ReadAll(body)
	if size != 5 || string(data) != "ID3xy" {
		t.Fatalf("download = %d %q", size, data)
	}
}

func TestErrorsNeverContainTheToken(t *testing.T) {
	client := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, `{"ok":false,"error_code":400,"description":"Bad Request: file is too big"}`)
	})
	if _, _, err := client.Open(context.Background(), "f"); !errors.Is(err, bot.ErrFileTooLarge) {
		t.Fatalf("too big: %v", err)
	}

	client.config.BaseURL = "http://127.0.0.1:1"
	err := client.Send(context.Background(), "1", "x")
	if err == nil || strings.Contains(err.Error(), "secret-token") {
		t.Fatalf("connection error leaks the token: %v", err)
	}
}
