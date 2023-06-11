package internal

import (
	"context"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/client"
)

// NewDockerClinet returns a new docker client
// The client is configured to use the default docker environment
// and an the internal's package default http client with a 15 second timeout
func NewDockerClient() (*client.Client, error) {
	docker, err := client.NewClientWithOpts(
		client.FromEnv,
		client.WithAPIVersionNegotiation(),
		client.WithHTTPClient(DefaultHTTPClient()),
		client.WithTimeout(15*time.Second),
		client.WithHTTPHeaders(map[string]string{
			"User-Agent": GetUserAgentString(Version),
		}),
	)
	if err != nil {

		return nil, err
	}
	return docker, err
}

// ListPaletteImages lists the images created by the build script
func listPaletteImages(ctx context.Context, d *client.Client, u UserSelections) ([]string, error) {

	var output []string

	images, err := d.ImageList(ctx, types.ImageListOptions{
		Filters: filters.NewArgs(filters.Arg("reference", "*/*:"+u.CustomTag)),
	})
	if err != nil {
		return output, err
	}

	for _, image := range images {
		for _, tag := range image.RepoTags {
			output = append(output, tag)
		}
	}

}
