package cli

import "github.com/spf13/cobra"

func (a *app) projectCommand() *cobra.Command {
	cmd := &cobra.Command{Use: "project", Short: "Project commands"}
	cmd.AddCommand(&cobra.Command{
		Use:   "list",
		Short: "List projects",
		RunE: func(cmd *cobra.Command, args []string) error {
			client, _, err := a.client()
			if err != nil {
				return err
			}
			raw, _, err := client.Projects(cmd.Context())
			if err != nil {
				return err
			}
			return writeRawJSON(a.stdout, raw)
		},
	})
	return cmd
}
