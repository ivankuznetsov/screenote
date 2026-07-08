package cli

import (
	"github.com/ivankuznetsov/screenote/internal/screenote"
	"github.com/spf13/cobra"
)

func (a *app) annotationCommand() *cobra.Command {
	cmd := &cobra.Command{Use: "annotation", Short: "Annotation commands"}

	var screenshotID, status, viewport string
	var limit, offset int
	list := &cobra.Command{
		Use:   "list",
		Short: "List annotations",
		RunE: func(cmd *cobra.Command, args []string) error {
			client, resolved, err := a.client()
			if err != nil {
				return err
			}
			query := screenote.WithLimitOffset(screenote.Query(map[string]string{
				"status":   status,
				"viewport": viewport,
			}), limit, offset)
			if screenshotID != "" {
				raw, _, err := client.Annotations(cmd.Context(), screenshotID, query)
				if err != nil {
					return err
				}
				return writeRawJSON(a.stdout, raw)
			}

			project, err := a.projectID(cmd.Context(), client, resolved)
			if err != nil {
				return err
			}
			_, screenshots, err := client.Screenshots(cmd.Context(), project, screenote.WithLimitOffset(screenote.Query(nil), 100, 0))
			if err != nil {
				return err
			}
			annotations := make([]screenote.Annotation, 0)
			for _, screenshot := range screenshots.Screenshots {
				_, response, err := client.Annotations(cmd.Context(), intString(screenshot.ID), query)
				if err != nil {
					return err
				}
				annotations = append(annotations, response.Annotations...)
			}
			return writeJSON(a.stdout, map[string]any{
				"annotations": annotations,
				"pagination": map[string]int{
					"total":  len(annotations),
					"limit":  limit,
					"offset": offset,
				},
			})
		},
	}
	list.Flags().StringVar(&screenshotID, "screenshot", "", "Screenshot ID")
	list.Flags().StringVar(&status, "status", "", "Annotation status")
	list.Flags().StringVar(&viewport, "viewport", "", "Viewport")
	list.Flags().IntVar(&limit, "limit", 50, "Maximum results")
	list.Flags().IntVar(&offset, "offset", 0, "Results to skip")

	var annotationID string
	get := &cobra.Command{
		Use:   "get",
		Short: "Get annotation details",
		RunE: func(cmd *cobra.Command, args []string) error {
			if annotationID == "" {
				return missingFlag("annotation")
			}
			client, _, err := a.client()
			if err != nil {
				return err
			}
			raw, err := client.Annotation(cmd.Context(), annotationID)
			if err != nil {
				return err
			}
			return writeRawJSON(a.stdout, raw)
		},
	}
	get.Flags().StringVar(&annotationID, "annotation", "", "Annotation ID")

	cmd.AddCommand(list, get)
	return cmd
}
