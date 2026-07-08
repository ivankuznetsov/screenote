package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

	"github.com/ivankuznetsov/screenote/internal/screenote"
)

const (
	ExitOK          = 0
	ExitGeneric     = 1
	ExitUsage       = 2
	ExitAuth        = 3
	ExitNotFound    = 4
	ExitRateLimited = 5
)

type cliError struct {
	Code    string
	Message string
	Exit    int
}

func (e *cliError) Error() string { return e.Message }

func usageError(code, message string) error {
	return &cliError{Code: code, Message: message, Exit: ExitUsage}
}

func writeError(w io.Writer, err error) int {
	code := "internal_error"
	message := err.Error()
	exitCode := ExitGeneric

	var ce *cliError
	if errors.As(err, &ce) {
		code = ce.Code
		message = ce.Message
		exitCode = ce.Exit
	} else {
		var se *screenote.Error
		if errors.As(err, &se) {
			code = se.Code
			message = se.Message
			exitCode = exitForHTTP(se.StatusCode)
		}
	}

	_ = json.NewEncoder(w).Encode(map[string]string{
		"error": message,
		"code":  code,
	})
	return exitCode
}

func exitForHTTP(status int) int {
	switch status {
	case http.StatusUnauthorized, http.StatusForbidden:
		return ExitAuth
	case http.StatusNotFound:
		return ExitNotFound
	case http.StatusTooManyRequests:
		return ExitRateLimited
	default:
		return ExitGeneric
	}
}

func missingFlag(name string) error {
	return usageError("missing_"+name, fmt.Sprintf("--%s is required", name))
}
