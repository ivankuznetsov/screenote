package cli

import "github.com/spf13/cobra"

func (a *app) pageCommand() *cobra.Command {
	cmd := &cobra.Command{Use: "page", Short: "Page commands"}
	cmd.AddCommand(&cobra.Command{
		Use:   "list",
		Short: "List pages",
		RunE: func(cmd *cobra.Command, args []string) error {
			client, resolved, err := a.client()
			if err != nil {
				return err
			}
			project, err := a.projectID(cmd.Context(), client, resolved)
			if err != nil {
				return err
			}
			raw, err := client.Pages(cmd.Context(), project)
			if err != nil {
				return err
			}
			return writeRawJSON(a.stdout, raw)
		},
	})
	return cmd
}
