package screenote

import "encoding/json"

type Project struct {
	ID              int    `json:"id"`
	Name            string `json:"name"`
	Role            string `json:"role,omitempty"`
	ScreenshotCount int    `json:"screenshot_count"`
	CreatedAt       string `json:"created_at"`
}

type ProjectsResponse struct {
	Projects []Project `json:"projects"`
}

type Page struct {
	ID           int    `json:"id"`
	Name         string `json:"name"`
	VersionCount int    `json:"version_count"`
	URL          string `json:"url"`
	CreatedAt    string `json:"created_at"`
}

type Pagination struct {
	Total  int `json:"total"`
	Limit  int `json:"limit"`
	Offset int `json:"offset"`
}

type ScreenshotImage struct {
	ID       int    `json:"id"`
	Viewport string `json:"viewport"`
	Status   string `json:"status"`
	Width    *int   `json:"width"`
	Height   *int   `json:"height"`
	Attached bool   `json:"attached"`
}

type Screenshot struct {
	ID              int               `json:"id"`
	Title           string            `json:"title"`
	PageID          int               `json:"page_id"`
	PageName        string            `json:"page_name"`
	Status          string            `json:"status"`
	AnnotationCount int               `json:"annotation_count"`
	UnresolvedCount int               `json:"unresolved_count"`
	AnnotateURL     string            `json:"annotate_url"`
	Viewports       []ScreenshotImage `json:"viewports"`
	CreatedAt       string            `json:"created_at"`
}

type ScreenshotsResponse struct {
	Screenshots []Screenshot `json:"screenshots"`
	Pagination  Pagination   `json:"pagination"`
}

type Coordinates struct {
	XPercent      float64  `json:"x_percent"`
	YPercent      float64  `json:"y_percent"`
	WidthPercent  *float64 `json:"width_percent"`
	HeightPercent *float64 `json:"height_percent"`
}

// Attachment is one image posted with a native browser message. URL is minted
// per read and expires; it is never durable, so callers must fetch it while
// UrlExpiresAt is still in the future and always with their bearer credential.
type Attachment struct {
	ID           int     `json:"id"`
	AltText      *string `json:"alt_text"`
	MediaType    string  `json:"media_type"`
	Width        int     `json:"width"`
	Height       int     `json:"height"`
	Size         int64   `json:"size"`
	URL          string  `json:"url"`
	URLExpiresAt string  `json:"url_expires_at"`
}

// Attachments marshals as an array whenever the key was present at all. The
// service sends `attachments` on every detail read — empty rather than absent —
// so a decode-then-encode round trip keeps that contract instead of emitting
// null. List rows carry no attachment metadata and omit the key entirely; the
// pointer fields below preserve that difference, because re-adding an empty
// array there would assert "this message has no images" about a message whose
// images are only reported on a detail read.
type Attachments []Attachment

func (a Attachments) MarshalJSON() ([]byte, error) {
	if a == nil {
		return []byte("[]"), nil
	}

	return json.Marshal([]Attachment(a))
}

type Annotation struct {
	ID                 int          `json:"id"`
	ScreenshotID       int          `json:"screenshot_id"`
	Viewport           string       `json:"viewport"`
	Type               string       `json:"type"`
	Coordinates        Coordinates  `json:"coordinates"`
	Comment            string       `json:"comment"`
	Status             string       `json:"status"`
	Author             string       `json:"author"`
	CommentsCount      int          `json:"comments_count"`
	CreatedAt          string       `json:"created_at"`
	ScreenshotStatus   string       `json:"screenshot_status,omitempty"`
	CroppedImageBase64 *string      `json:"cropped_image_base64,omitempty"`
	MIMEType           string       `json:"mime_type,omitempty"`
	Attachments        *Attachments `json:"attachments,omitempty"`
	Comments           []Comment    `json:"comments,omitempty"`
}

type AnnotationsResponse struct {
	Annotations []Annotation `json:"annotations"`
	Pagination  Pagination   `json:"pagination"`
}

type Comment struct {
	ID           int          `json:"id"`
	AnnotationID int          `json:"annotation_id,omitempty"`
	Action       string       `json:"action"`
	Body         string       `json:"body"`
	Author       string       `json:"author"`
	CreatedAt    string       `json:"created_at"`
	Attachments  *Attachments `json:"attachments,omitempty"`
}
