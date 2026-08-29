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
	if len(annotation.Attachments) != 1 {
		t.Fatalf("expected one root attachment, got %d", len(annotation.Attachments))
	}

	root := annotation.Attachments[0]
	if root.ID != 11 || root.MediaType != "image/png" || root.Width != 800 || root.Size != 12345 {
		t.Fatalf("root attachment metadata lost: %+v", root)
	}
	if root.AltText == nil || *root.AltText != "The disabled save button" {
		t.Fatalf("alt text lost: %+v", root.AltText)
	}
	if root.URLExpiresAt != "2026-08-29T00:05:00Z" {
		t.Fatalf("url expiry lost: %q", root.URLExpiresAt)
	}

	if len(annotation.Comments) != 1 || len(annotation.Comments[0].Attachments) != 1 {
		t.Fatalf("comment attachments lost: %+v", annotation.Comments)
	}
	if annotation.Comments[0].Attachments[0].AltText != nil {
		t.Fatalf("absent alt text must decode as nil")
	}
	if annotation.Comments[0].Body != "Here is the crop" {
		t.Fatalf("shipped comment fields changed: %+v", annotation.Comments[0])
	}
}

func TestAnnotationWithoutAttachmentsDecodes(t *testing.T) {
	var annotation Annotation
	if err := json.Unmarshal([]byte(`{"id": 1, "comment": "No images", "attachments": []}`), &annotation); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(annotation.Attachments) != 0 {
		t.Fatalf("expected no attachments, got %d", len(annotation.Attachments))
	}
}
