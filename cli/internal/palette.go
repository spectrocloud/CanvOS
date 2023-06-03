package internal

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/rs/zerolog/log"
)

// GetPacks returns information about the packs.
// The query parameters are passed in as a string.
// Example: "filters=spec.cloudTypes=edge-nativeANDspec.layer=cni&limit=50&orderBy=spec.version=-1"
func GetPacks(ctx context.Context, p PaletteAuth, queryParams string) (Packs, error) {

	urlReq := p.Host + "/v1/packs?" + queryParams

	// get the OS pack
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
		req.Header.Add("ProjectId", p.ProjectID)
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
