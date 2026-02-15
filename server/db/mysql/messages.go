// Package mysql - Cats Company message database operations.
package mysql

import (
	"fmt"

	"github.com/openchat/openchat/server/store/types"
)

// CreateTopic creates a topic if it doesn't exist.
func (a *Adapter) CreateTopic(id, topicType string, ownerID int64) error {
	_, err := a.db.Exec(
		`INSERT IGNORE INTO topics (id, type, owner_id) VALUES (?, ?, ?)`,
		id, topicType, ownerID,
	)
	return err
}

// SaveMessage inserts a message and returns its ID.
func (a *Adapter) SaveMessage(topicID string, fromUID int64, content, msgType string) (int64, error) {
	res, err := a.db.Exec(
		`INSERT INTO messages (topic_id, from_uid, content, msg_type) VALUES (?, ?, ?, ?)`,
		topicID, fromUID, content, msgType,
	)
	if err != nil {
		return 0, fmt.Errorf("save message: %w", err)
	}
	return res.LastInsertId()
}

// GetMessagesSince returns messages after a given ID for a topic.
func (a *Adapter) GetMessagesSince(topicID string, sinceID int64, limit int) ([]*types.Message, error) {
	if limit <= 0 {
		limit = 50
	}
	rows, err := a.db.Query(
		`SELECT id, topic_id, from_uid, content, msg_type, created_at
		 FROM messages WHERE topic_id = ? AND id > ?
		 ORDER BY id ASC LIMIT ?`,
		topicID, sinceID, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("get messages since: %w", err)
	}
	defer rows.Close()

	var msgs []*types.Message
	for rows.Next() {
		m := &types.Message{}
		if err := rows.Scan(&m.ID, &m.TopicID, &m.FromUID, &m.Content, &m.MsgType, &m.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan message: %w", err)
		}
		msgs = append(msgs, m)
	}
	return msgs, rows.Err()
}

// GetMessages returns messages for a topic, ordered by time.
func (a *Adapter) GetMessages(topicID string, limit, offset int) ([]*types.Message, error) {
	if limit <= 0 {
		limit = 50
	}
	rows, err := a.db.Query(
		`SELECT id, topic_id, from_uid, content, msg_type, created_at
		 FROM messages WHERE topic_id = ?
		 ORDER BY created_at ASC LIMIT ? OFFSET ?`,
		topicID, limit, offset,
	)
	if err != nil {
		return nil, fmt.Errorf("get messages: %w", err)
	}
	defer rows.Close()

	var msgs []*types.Message
	for rows.Next() {
		m := &types.Message{}
		if err := rows.Scan(&m.ID, &m.TopicID, &m.FromUID, &m.Content, &m.MsgType, &m.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan message: %w", err)
		}
		msgs = append(msgs, m)
	}
	return msgs, rows.Err()
}
