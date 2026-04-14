// Package server implements Cats Company message-related API handlers.
package server

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/openchat/openchat/server/db/mysql"
	"github.com/openchat/openchat/server/store/types"
)

// MessageHandler handles message-related API requests.
type MessageHandler struct {
	db  *mysql.Adapter
	hub *Hub
}

// NewMessageHandler creates a new MessageHandler.
func NewMessageHandler(db *mysql.Adapter, hub *Hub) *MessageHandler {
	return &MessageHandler{db: db, hub: hub}
}

// SendMessageRequest is the JSON body for sending a message.
type SendMessageRequest struct {
	TopicID       string               `json:"topic_id"`
	Content       string               `json:"content,omitempty"`
	ContentBlocks []types.ContentBlock `json:"content_blocks,omitempty"`
	MsgType       string               `json:"msg_type,omitempty"`
	Type          string               `json:"type,omitempty"`
	Mode          string               `json:"mode,omitempty"`
	Role          string               `json:"role,omitempty"`
	ReplyTo       int                  `json:"reply_to,omitempty"`
}

// HandleSendMessage handles POST /api/messages/send
func (h *MessageHandler) HandleSendMessage(w http.ResponseWriter, r *http.Request) {
	uid := UIDFromContext(r.Context())

	var req SendMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request"})
		return
	}

	if (req.Content == "" && len(req.ContentBlocks) == 0) || req.TopicID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "topic_id and content/content_blocks required"})
		return
	}

	msgType := req.MsgType
	if msgType == "" {
		msgType = req.Type
	}
	if msgType == "" {
		msgType = "text"
	}

	if !isGroupTopic(req.TopicID) {
		// Ensure p2p topic exists before saving.
		h.db.CreateTopic(req.TopicID, "p2p", uid)
	}

	var id int64
	var err error

	// Use new API if content_blocks provided.
	if len(req.ContentBlocks) > 0 {
		mode := req.Mode
		if mode == "" {
			mode = "code"
		}
		id, err = h.db.SaveMessageWithBlocks(req.TopicID, uid, req.Content, req.ContentBlocks, mode, req.Role, msgType)
	} else if req.ReplyTo > 0 {
		id, err = h.db.SaveMessageWithReply(req.TopicID, uid, req.Content, msgType, int64(req.ReplyTo))
	} else {
		id, err = h.db.SaveMessage(req.TopicID, uid, req.Content, msgType)
	}

	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to send"})
		return
	}

	resp := map[string]interface{}{
		"id":       id,
		"seq_id":   id,
		"topic_id": req.TopicID,
		"from_uid": uid,
		"msg_type": msgType,
		"reply_to": req.ReplyTo,
	}
	if len(req.ContentBlocks) > 0 {
		resp["content_blocks"] = req.ContentBlocks
		resp["mode"] = req.Mode
		resp["role"] = req.Role
	} else {
		resp["content"] = req.Content
	}

	h.fanoutMessage(uid, &req, id)
	writeJSON(w, http.StatusOK, resp)
}

func (h *MessageHandler) fanoutMessage(uid int64, req *SendMessageRequest, msgID int64) {
	if h == nil || h.hub == nil || req == nil {
		return
	}

	dataMsg := &ServerMessage{
		Data: &MsgServerData{
			Topic:   req.TopicID,
			From:    formatUID(uid),
			SeqID:   int(msgID),
			Content: req.Content,
			ReplyTo: req.ReplyTo,
		},
	}

	if isGroupTopic(req.TopicID) {
		groupID := extractGroupID(req.TopicID)
		if groupID == 0 {
			return
		}
		mentions := parseMentions(req.Content)
		dataMsg.Data.Mentions = mentions
		h.hub.SendToUserExcept(uid, dataMsg, nil)
		h.hub.broadcastToGroupWithMentions(groupID, dataMsg, uid, mentions, uid)
		return
	}

	peerUID := extractPeerUID(req.TopicID, uid)
	if peerUID == 0 {
		return
	}

	h.hub.SendToUserExcept(uid, dataMsg, nil)
	h.hub.SendToUser(peerUID, dataMsg)

	if senderClient := h.hub.getClient(uid); senderClient != nil && senderClient.accountType == types.AccountBot {
		h.hub.botStats.RecordSent(uid, req.TopicID)
	}
	if peerClient := h.hub.getClient(peerUID); peerClient != nil && peerClient.accountType == types.AccountBot {
		h.hub.botStats.RecordRecv(peerUID)
	}
}

// HandleGetMessages handles GET /api/messages?topic_id=xxx&limit=50&offset=0
func (h *MessageHandler) HandleGetMessages(w http.ResponseWriter, r *http.Request) {
	_ = UIDFromContext(r.Context())

	topicID := r.URL.Query().Get("topic_id")
	if topicID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "topic_id required"})
		return
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	latest := r.URL.Query().Get("latest") == "1" || r.URL.Query().Get("latest") == "true"

	var msgs interface{}
	var err error
	if latest {
		msgs, err = h.db.GetLatestMessages(topicID, limit, offset)
	} else {
		msgs, err = h.db.GetMessages(topicID, limit, offset)
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to load messages"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"messages": msgs})
}
