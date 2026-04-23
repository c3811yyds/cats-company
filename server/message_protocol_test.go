package server

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestPubMessageNormalizesLikeHTTPRequest(t *testing.T) {
	cases := []struct {
		name     string
		content  json.RawMessage
		msgType  string
		metadata map[string]interface{}
	}{
		{
			name:    "tool use",
			content: json.RawMessage(`"glob"`),
			msgType: "tool_use",
			metadata: map[string]interface{}{
				"id": "call_1",
				"input": map[string]interface{}{
					"pattern": "**/*.md",
				},
			},
		},
		{
			name:    "image content",
			content: json.RawMessage(`{"type":"image","payload":{"url":"/uploads/a.png","name":"a.png","size":12}}`),
			msgType: "image",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			httpPayload, err := normalizeMessageRequest(&SendMessageRequest{
				TopicID:  "grp_80",
				Type:     tc.msgType,
				Content:  tc.content,
				Metadata: tc.metadata,
			})
			if err != nil {
				t.Fatalf("normalize HTTP request: %v", err)
			}

			wsReq := messageRequestFromPub(&MsgClientPub{
				Topic:    "grp_80",
				Type:     tc.msgType,
				Content:  tc.content,
				Metadata: tc.metadata,
			})
			wsPayload, err := normalizeMessageRequest(wsReq)
			if err != nil {
				t.Fatalf("normalize WebSocket pub: %v", err)
			}

			if !reflect.DeepEqual(httpPayload, wsPayload) {
				t.Fatalf("payload mismatch\nHTTP: %#v\nWS:   %#v", httpPayload, wsPayload)
			}
		})
	}
}
