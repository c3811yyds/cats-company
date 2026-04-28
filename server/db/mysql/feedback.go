// Package mysql - Cats Company feedback database operations.
package mysql

import (
	"encoding/json"
	"fmt"

	"github.com/openchat/openchat/server/store/types"
)

// CreateFeedbackReport inserts a user feedback report and returns its ID.
func (a *Adapter) CreateFeedbackReport(report *types.FeedbackReport) (int64, error) {
	if report == nil {
		return 0, fmt.Errorf("feedback report is nil")
	}

	var attachmentsJSON []byte
	var err error
	if len(report.Attachments) > 0 {
		attachmentsJSON, err = json.Marshal(report.Attachments)
		if err != nil {
			return 0, fmt.Errorf("marshal feedback attachments: %w", err)
		}
	}

	res, err := a.db.Exec(
		`INSERT INTO feedback_reports
		 (user_id, category, title, description, page_url, user_agent, attachments)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		report.UserID,
		report.Category,
		report.Title,
		report.Description,
		report.PageURL,
		report.UserAgent,
		attachmentsJSON,
	)
	if err != nil {
		return 0, fmt.Errorf("create feedback report: %w", err)
	}
	return res.LastInsertId()
}
