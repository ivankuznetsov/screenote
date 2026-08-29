package screenote

import (
	"encoding/json"
	"testing"
)

// The service always sends `attachments` on the root annotation and on every
// comment of a detail read. Decoding must keep the metadata and the expiring
// URL intact without disturbing any previously shipped field.
func TestAnnotationDetailDecodesAttachments(t *testing.T) {
	payload := []byte(`{
		"id": 7,
		"screenshot_id": 3,
		"viewport": "desktop",
		"type": "region",
		"coordinates": {"x_percent": 1.0, "y_percent": 2.0, "width_percent": 3.0, "height_percent": 4.0},
		"comment": "Broken button",
		"status": "open",
		"author": "alice@example.com",
		"comments_count": 1,
		"created_at": "2026-08-29T00:00:00Z",
		"screenshot_status": "ready",
		"mime_type": "image/png",
		"attachments": [
			{
				"id": 11,
				"alt_text": "The disabled save button",
				"media_type": "image/png",
				"width": 800,
				"height": 600,
				"size": 12345,
				"url": "https://screenote.test/api/media/image_attachments/11?token=abc",
				"url_expires_at": "2026-08-29T00:05:00Z"
			}
		],
		"comments": [
			{
				"id": 21,
				"action": "comment",
				"body": "Here is the crop",
				"author": "bob@example.com",
				"created_at": "2026-08-29T00:01:00Z",
				"attachments": [
					{
						"id": 12,
						"alt_text": null,
						"media_type": "image/webp",
						"width": 100,
						"height": 50,
						"size": 900,
						"url": "https://screenote.test/api/media/image_attachments/12?token=def",
						"url_expires_at": "2026-08-29T00:05:00Z"
					}
				]
			}
		]
	}`)

	var annotation Annotation
	if err := json.Unmarshal(payload, &annotation); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if annotation.Comment != "Broken button" || annotation.MIMEType != "image/png" {
		t.Fatalf("shipped annotation fields changed: %+v", annotation)
	}
	if annotation.Attachments == nil || len(*annotation.Attachments) != 1 {
		t.Fatalf("expected one root attachment, got %+v", annotation.Attachments)
	}

	root := (*annotation.Attachments)[0]
	if root.ID != 11 || root.MediaType != "image/png" || root.Width != 800 || root.Size != 12345 {
		t.Fatalf("root attachment metadata lost: %+v", root)
	}
	if root.AltText == nil || *root.AltText != "The disabled save button" {
		t.Fatalf("alt text lost: %+v", root.AltText)
	}
	if root.URLExpiresAt != "2026-08-29T00:05:00Z" {
		t.Fatalf("url expiry lost: %q", root.URLExpiresAt)
	}

	if len(annotation.Comments) != 1 || annotation.Comments[0].Attachments == nil ||
		len(*annotation.Comments[0].Attachments) != 1 {
		t.Fatalf("comment attachments lost: %+v", annotation.Comments)
	}
	if (*annotation.Comments[0].Attachments)[0].AltText != nil {
		t.Fatalf("absent alt text must decode as nil")
	}
	if annotation.Comments[0].Body != "Here is the crop" {
		t.Fatalf("shipped comment fields changed: %+v", annotation.Comments[0])
	}
}

// A detail read for a message with no images sends an empty array, and that is
// an authoritative "no images" the round trip must preserve.
func TestEmptyAttachmentsRemarshalAsAnArray(t *testing.T) {
	var annotation Annotation
	payload := `{"id": 1, "comment": "No images", "attachments": [], "comments": [{"id": 2, "attachments": []}]}`
	if err := json.Unmarshal([]byte(payload), &annotation); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if annotation.Attachments == nil || len(*annotation.Attachments) != 0 {
		t.Fatalf("an empty array must decode as present and empty: %+v", annotation.Attachments)
	}

	remarshalled := remarshal(t, annotation)
	attachments, ok := remarshalled["attachments"].([]any)
	if !ok || len(attachments) != 0 {
		t.Fatalf("root attachments must remarshal as an empty array: %+v", remarshalled)
	}

	comments, ok := remarshalled["comments"].([]any)
	if !ok || len(comments) != 1 {
		t.Fatalf("expected one comment: %+v", remarshalled)
	}
	commentAttachments, ok := comments[0].(map[string]any)["attachments"].([]any)
	if !ok || len(commentAttachments) != 0 {
		t.Fatalf("comment attachments must remarshal as an empty array: %+v", remarshalled)
	}
}

// List rows carry no attachment metadata at all. Re-encoding one must not
// invent `attachments: []`, which would tell an agent the message has no
// images and stop it from ever asking for the detail read that reports them.
func TestListRowsKeepAttachmentsAbsent(t *testing.T) {
	var annotation Annotation
	payload := `{"id": 1, "comment": "Only a list row", "comments_count": 2}`
	if err := json.Unmarshal([]byte(payload), &annotation); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if annotation.Attachments != nil {
		t.Fatalf("an absent key must decode as nil: %+v", annotation.Attachments)
	}

	remarshalled := remarshal(t, annotation)
	if _, present := remarshalled["attachments"]; present {
		t.Fatalf("a list row must not gain an attachments key: %+v", remarshalled)
	}

	comment := remarshal(t, Comment{ID: 2})
	if _, present := comment["attachments"]; present {
		t.Fatalf("a comment without attachments must not gain the key: %+v", comment)
	}
}

func remarshal(t *testing.T, value any) map[string]any {
	t.Helper()

	encoded, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	return decoded
}
