package internal

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/rs/zerolog/log"
)

// GetPacks returns information about the packs.
// The query parameters are passed in as a string.
// Example: "filters=spec.cloudTypes=edge-nativeANDspec.layer=cni&limit=50&orderBy=spec.version=-1"
func GetPacks(ctx context.Context, p PaletteAuth, queryParams string) (Packs, error) {

	urlReq := p.Host + "/v1/packs?" + queryParams

	httpClient := DefaultHTTPClient()

	req, err := http.NewRequest("GET", urlReq, nil)
	if err != nil {
		log.Info().Msg("Error creating a pack information request")
		log.Debug().Err(err).Msg(queryParams)
		LogError(err)
	}

	req.Header.Add("Content-Type", "application/json")
	req.Header.Add("Accept", "application/json")
	req.Header.Add("ApiKey", p.APIKey)

	if p.ProjectID != "" {
		req.Header.Add("ProjectUid", p.ProjectID)
	}

	req.Header.Add("User-Agent", GetUserAgentString(Version))

	response, err := httpClient.Do(req)
	if err != nil {
		log.Info().Msg("Error retrieving the pack information from Palette")
		log.Debug().Err(err).Msg(queryParams)
		LogError(err)
	}

	defer response.Body.Close()

	log.Debug().Msgf("HTTP Request Status: %s", response.Status)
	log.Debug().Interface("Respose Body", response.Body)

	if response.StatusCode != 200 {
		var responseError PaletteAPIError
		err = json.NewDecoder(response.Body).Decode(&responseError)
		if err != nil {
			log.Info().Msg("Error converting the pack information to JSON")
			LogError(err)
			return Packs{}, err
		}
		return Packs{}, errors.New(responseError.Message)
	}

	var responseData Packs
	err = json.NewDecoder(response.Body).Decode(&responseData)
	if err != nil {
		log.Info().Msg("Error converting the pack information to JSON")
		log.Debug().Err(err).Msg(queryParams)
		LogError(err)
		return Packs{}, err
	}

	return responseData, err

}

// GetPaletteVersions returns information about the available Palette Edge Installer versions.
func GetPaletteVersions(ctx context.Context, p PaletteAuth) ([]string, error) {

	// TODO - Waiting on OPS-1657 to be completed to dyanmically retrieve the Palette Edge Installer versions
	// https://spectrocloud.atlassian.net/browse/OPS-1657?atlOrigin=eyJpIjoiY2NkNTQ5MjliOWFmNDY1NTg5MjA1MDZmYjkyNDNmNDEiLCJwIjoiamlyYS1zbGFjay1pbnQifQ

	return []string{
		"3.4.3",
		"3.4.2",
		"3.4.1",
		"3.4.0",
		"3.3.3",
		"3.3.2",
		"3.3.1",
		"3.3.0",
	}, nil

}

// CreateClusterProfileInPalette creates a new cluster profile in Palette.
func CreateClusterProfileInPalette(ctx context.Context, p PaletteAuth, cp ClusterProfile) (CreateClusterProfileResponse, error) {

	urlReq := p.Host + "/v1/clusterprofiles"

	httpClient := DefaultHTTPClient()

	jsonValue, err := cp.mashallClusterProfile()
	if err != nil {
		log.Info().Msg("Error marshalling the cluster profile")
		log.Debug().Err(err)
		LogError(err)
		return CreateClusterProfileResponse{}, err
	}

	payload := strings.NewReader(jsonValue)

	req, err := http.NewRequest("POST", urlReq, payload)
	if err != nil {
		log.Info().Msg("Error creating a cluster profile request")
		log.Debug().Err(err)
		LogError(err)
	}

	req.Header.Add("Content-Type", "application/json")
	req.Header.Add("Accept", "application/json")
	req.Header.Add("ApiKey", p.APIKey)

	if p.ProjectID != "" {
		req.Header.Add("ProjectUid", p.ProjectID)
	}

	req.Header.Add("User-Agent", GetUserAgentString(Version))

	response, err := httpClient.Do(req)
	if err != nil {
		log.Info().Msg("Error retrieving the pack information from Palette")
		LogError(err)
		return CreateClusterProfileResponse{}, err
	}

	defer response.Body.Close()

	if response.StatusCode != 201 {
		var responseError PaletteAPIError
		err = json.NewDecoder(response.Body).Decode(&responseError)
		if err != nil {
			log.Info().Msg("Error converting the pack information to JSON")
			LogError(err)
			return CreateClusterProfileResponse{}, err
		}
		return CreateClusterProfileResponse{}, errors.New(responseError.Message)
	}

	var responseData CreateClusterProfileResponse
	err = json.NewDecoder(response.Body).Decode(&responseData)
	if err != nil {
		log.Info().Msg("Error converting the pack information to JSON")
		LogError(err)
		return CreateClusterProfileResponse{}, err
	}

	return responseData, err

}

// PublishClusterProfileInPalette publishes a cluster profile in Palette.
func PublishClusterProfileInPalette(ctx context.Context, p PaletteAuth, cp CreateClusterProfileResponse) error {

	urlReq := p.Host + "/v1/clusterprofiles/" + cp.UID + "/publish"

	httpClient := DefaultHTTPClient()

	req, err := http.NewRequest("PATCH", urlReq, nil)
	if err != nil {
		log.Info().Msg("Error creating a cluster profile request")
		log.Debug().Err(err)
		LogError(err)
	}

	req.Header.Add("Content-Type", "application/json")
	req.Header.Add("Accept", "application/json")
	req.Header.Add("ApiKey", p.APIKey)

	if p.ProjectID != "" {
		req.Header.Add("ProjectUid", p.ProjectID)
	}

	req.Header.Add("User-Agent", GetUserAgentString(Version))

	response, err := httpClient.Do(req)
	if err != nil {
		log.Info().Msg("Error retrieving the pack information from Palette")
		LogError(err)
		return err
	}

	defer response.Body.Close()

	if response.StatusCode != 204 {
		var responseError PaletteAPIError
		err = json.NewDecoder(response.Body).Decode(&responseError)
		if err != nil {
			log.Info().Msg("Error converting the pack information to JSON")
			LogError(err)
			return err
		}
		return errors.New(responseError.Message)
	}

	return err

}
