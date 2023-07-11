package internal

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/client"
	"golang.org/x/sync/errgroup"
	log "specrocloud.com/canvos/logger"
)

// NewDockerClinet returns a new docker client
// The client is configured to use the default docker environment variables, API version negotiation, TLS configuration from environment variables (if available).
// The internal's package default http client with a 30 second timeout.
func NewDockerClient() (*client.Client, error) {
	docker, err := client.NewClientWithOpts(
		client.FromEnv,
		client.WithAPIVersionNegotiation(),
		client.WithTLSClientConfigFromEnv(),
		client.WithTimeout(300*time.Second),
		client.WithHTTPHeaders(map[string]string{
			"User-Agent": GetUserAgentString(Version),
		}),
	)
	if err != nil {
		return nil, err
	}
	return docker, err
}

// PushProviderImages pushes the container provider images created by the build script to the image registry provided by the user.
// This function acts as a main orchestrator for the image push process.
func PushProviderImages(ctx context.Context, d *client.Client, encodedCredentials string, u UserSelections) error {

	// Validate that the images exist
	images, err := validateImagesExist(ctx, d, u)
	if err != nil {
		return errors.New("no Edge provider images found. Try to issue the build command again")
	}

	g, ctx := errgroup.WithContext(ctx)

	// Push the images to the registry
	for index, imageName := range images {
		index := index
		imageName := imageName
		g.Go(func() error {
			var err error
			reader, err := pushImage(ctx, d, imageName, encodedCredentials)
			if err != nil {
				log.Debug("err %s: ", err)
				errMessage := fmt.Sprintf("Error pushing the image %s to the registry. Error: %s", imageName, err.Error())
				return errors.New(errMessage)
			}

			// Process the stream output but only for the last image
			// This is to avoid printing the stream output multiple times
			// since the stream output is the same for all images

			if index == len(images)-1 {

				err = processStream(reader)
				if err != nil {
					log.Debug("err %s: ", err)
					log.Info("Error processing the image upload stream output")
				}

			}

			return err
		})

	}

	// Wait for all requests to finish
	if err := g.Wait(); err != nil {
		log.FatalCLI("Error pushing the images to the registry")

	}

	return nil

}

// validateImagesExist validates that the container provider images created by the build script exist.
// The function returns a boolean value indicating if the images exist or not.
// If the images exist, the function returns a slice of strings containing the images names.
func validateImagesExist(ctx context.Context, d *client.Client, u UserSelections) ([]string, error) {

	var imagesOutput []string

	repositoryFilter := fmt.Sprintf("%s/%s", u.ImageRegistryURL, u.ImageRegistryRepository)

	images, err := d.ImageList(ctx, types.ImageListOptions{})
	if err != nil {
		log.InfoCLI(err.Error())
		return imagesOutput, err
	}

	for _, image := range images {
		for _, repoTag := range image.RepoTags {
			parts := strings.SplitN(repoTag, ":", 2)
			repository, tag := parts[0], parts[1]

			if strings.Contains(repository, repositoryFilter) && strings.Contains(tag, u.CustomTag) {
				imagesOutput = append(imagesOutput, repoTag)
			}
		}
	}

	if len(imagesOutput) == 0 {
		return imagesOutput, errors.New("no Edge provider images found. Try to issue the build command again")
	}

	return imagesOutput, nil
}

// pushImages pushes the container provider images created by the build script to the image registry provided by the user.
// The Docker client's HTTP client timeout is set to 300 seconds to allow for the images to be pushed to the registry.
func pushImage(ctx context.Context, d *client.Client, imageName string, authConfigEncoded string) (io.ReadCloser, error) {
	return d.ImagePush(ctx, imageName, types.ImagePushOptions{
		RegistryAuth: authConfigEncoded,
	})
}

// processStream processes the stream of data from the Docker client
// and prints the progress detail.
// The stream is closed when the reader is closed.
func processStream(reader io.ReadCloser) error {
	defer reader.Close()

	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		text := scanner.Text()
		progressDetail := make(map[string]interface{})

		err := json.Unmarshal([]byte(text), &progressDetail)
		if err != nil {
			return err
		}

		printProgressDetail(progressDetail)
	}

	return scanner.Err()
}

// printProgressDetail prints formatted progress detail
func printProgressDetail(progressDetail map[string]interface{}) {
	id, idOk := progressDetail["id"].(string)
	status, statusOk := progressDetail["status"].(string)
	progress, progressOk := progressDetail["progress"].(string)

	if idOk && statusOk {
		var output string
		if progressOk {
			output = fmt.Sprintf("ID: %s, Status: %s, Progress: %s\n", id, status, progress)
		} else {
			output = fmt.Sprintf("ID: %s, Status: %s\n", id, status)
		}

		log.InfoCLI("%s", output)
	}
}
