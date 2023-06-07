package prompts

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	wrap_errors "emperror.dev/errors"
	"github.com/chzyer/readline"
	"github.com/manifoldco/promptui"
	"github.com/manifoldco/promptui/list"
	"golang.org/x/exp/slices"
	"k8s.io/apimachinery/pkg/util/validation"

	log "github.com/spectrocloud/palette-cli/pkg/logging"
	"github.com/spectrocloud/palette-cli/tests/utils/test/mocks"
)

const (
	// Standard key mappings equate Delete with CTRL+D, which shouldn't
	// cause the TUI to crash. Users can still forcibly exit with CTRL+C.
	ctrlD = "^D"

	// Adapted from: http://stackoverflow.com/questions/10306690/domain-name-validation-with-regex/26987741#26987741
	idn         = "(-){0}(xn--)"
	idnOrPeriod = "(-){0}(xn--|.)"
	domain      = "?[a-z0-9][a-z0-9-_]{0,61}[a-z0-9]{0,1}\\.(xn--)?([a-z0-9\\-]{1,61}|[a-z0-9-]{1,30}\\.[a-z]{2,})"

	// Adapted from: https://stackoverflow.com/a/36760050/7898074, https://stackoverflow.com/a/12968117/7898074
	ip   = "((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}"
	port = ":([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])"
)

var (
	// Exported regex patterns for use with ReadTextRegex
	KindClusterRegex = "^[a-z0-9.-]+$"
	// Allowed chars are alphanumerics plus '.', '-', and '_', but cannot start or end with a symbol.
	// Additionally, 2+ consecutive symbols are disallowed.
	UsernameRegex            = "[a-zA-Z0-9]+(?:\\.[a-zA-Z0-9]+)*(?:-[a-zA-Z0-9]+)*(?:_[a-zA-Z0-9]+)*"
	PaletteResourceNameRegex = "[a-z][a-z0-9-]{1,31}[a-z0-9]"
	VSphereUsernameRegex     = "^" + UsernameRegex + "@" + domain + "$"

	noProxyExceptions  = []string{"*", "localhost"}
	domainRegex        = regexp.MustCompile("^" + idn + domain + "$")
	noProxyDomainRegex = regexp.MustCompile("^" + idnOrPeriod + domain + "$")
	domainPortRegex    = regexp.MustCompile("^" + idn + domain + port + "$")
	ipPortRegex        = regexp.MustCompile("^" + ip + port + "$")
)

// ---------
// Selection
// ---------

const numSelections = 15

var (
	// GetPrompt enables monkey patching of promptui.Prompt.Run()
	GetPrompter = promptuiPrompt

	// GetSelector enables monkey patching of promptui.Select.Run() in Select
	GetSelector = promptuiSelect

	// GetIDSelector enables monkey patching of promptui.Select.Run() in SelectID
	GetIDSelector = promptuiSelect

	// templates for Select
	stringTemplates = promptui.SelectTemplates{
		Label:    "{{ . }}?",
		Active:   "\u2713 {{ . | cyan }} ",
		Inactive: "  {{ . | blue }} ",
		Selected: "\u2713 {{ . | red | cyan }}",
	}

	// templates for SelectID
	choiceTemplates = promptui.SelectTemplates{
		Label:    "{{ . }}?",
		Active:   "\u2713 {{ .Name | cyan }} ",
		Inactive: "  {{ .Name | blue }} ",
		Selected: "\u2713 {{ .Name | red | cyan }}",
	}
)

// ChoiceItems are selected by SelectID
type ChoiceItem struct {
	ID   string
	Name string
}

// promptuiPrompt is the prompt Prompter used in production
func promptuiPrompt(label, defaultVal string, allowEdit, isConfirm bool, validate func(input string) error, mask *rune) mocks.PromptPrompter {
	prompt := &promptui.Prompt{
		AllowEdit: allowEdit,
		Default:   defaultVal,
		IsConfirm: isConfirm,
		Label:     label,
		Validate:  validate,
	}
	if mask != nil {
		prompt.Mask = *mask
	}
	return prompt
}

// promptuiSelect is the select Selector used in production
func promptuiSelect(items, label interface{}, searcher list.Searcher, size int, startInSearchMode bool, templates *promptui.SelectTemplates) mocks.SelectPrompter {
	return &promptui.Select{
		Items:             items,
		Label:             label,
		Searcher:          searcher,
		Size:              numSelections,
		StartInSearchMode: true,
		Templates:         templates,
		Stdout:            NoBellStdout,
	}
}

func sanitizedContains(str, needle string) bool {
	s := strings.TrimSpace(strings.ToLower(str))
	needle = strings.TrimSpace(strings.ToLower(needle))
	return strings.Contains(s, needle)
}

func stringSearcher(items []string) func(string, int) bool {
	searcher := func(input string, index int) bool {
		item := items[index]
		return sanitizedContains(item, input)
	}
	return searcher
}

func choiceSearcher(items []ChoiceItem) func(string, int) bool {
	searcher := func(input string, index int) bool {
		item := items[index]
		return sanitizedContains(item.Name, input)
	}
	return searcher
}

func Select(label string, items []string, defaultVal string, errMsg string) (string, error) {
	prompt := GetSelector(items, label, stringSearcher(items), numSelections, true, &stringTemplates)
	_, result, err := prompt.Run()
	if err != nil {
		if err.Error() == ctrlD {
			return Select(label, items, defaultVal, errMsg)
		}
		return result, wrap_errors.Wrap(err, "failure in Select")
	}
	return result, nil
}

func SelectID(label string, choices []ChoiceItem, defaultVal string, errMsg string) (ChoiceItem, error) {
	prompt := GetIDSelector(choices, label, choiceSearcher(choices), numSelections, true, &choiceTemplates)
	index, _, err := prompt.Run()
	if err != nil {
		if err.Error() == ctrlD {
			return SelectID(label, choices, defaultVal, errMsg)
		}
		return choices[index], wrap_errors.Wrap(err, "failure in SelectID")
	}
	return choices[index], nil
}

func CommaSeparatedSelections(selectedMap map[string]bool) string {
	var selected string
	for k, v := range selectedMap {
		if v {
			selected += k + ","
		}
	}
	selected = strings.TrimSuffix(selected, ",")
	return selected
}

func MultiSelectString(obj string, choices []ChoiceItem, selected map[string]bool) ([]string, error) {
	choicesLocal := make([]ChoiceItem, 0)
	for _, c := range choices {
		if !selected[c.Name] {
			choicesLocal = append(choicesLocal, c)
		}
	}
	choicesLocal = append(choicesLocal, ChoiceItem{ID: "Done", Name: "Done"})

	prompt := fmt.Sprintf(
		"Select one or more %ss. Currently selected: '%s'. Select 'Done' to finish",
		obj, CommaSeparatedSelections(selected),
	)
	val, err := SelectID(prompt, choicesLocal, "", fmt.Sprintf("Invalid %s", obj))
	if err != nil {
		return nil, err
	}

	if val.Name == "Done" {
		selectedIds := make([]string, 0, len(selected))
		for n := range selected {
			for _, c := range choices {
				if c.Name == n {
					selectedIds = append(selectedIds, c.ID)
				}
			}
		}
		return selectedIds, nil
	} else {
		selected[val.Name] = true
		return MultiSelectString(obj, choices, selected)
	}
}

// ---------------
// Input Functions
// ---------------

func ReadNoProxy(label, defaultVal, errMsg string, isOptional bool) (string, error) {

	validate := func(input string) error {
		if input == "" {
			if !isOptional {
				return errors.New(errMsg)
			} else {
				return nil
			}
		}
		// See: https://pkg.go.dev/golang.org/x/net/http/httpproxy#Config
		for _, v := range strings.Split(input, ",") {
			ip := net.ParseIP(v)
			isNoProxyDomain := noProxyDomainRegex.Match([]byte(v))
			_, _, cidrErr := net.ParseCIDR(v)
			isDomainWithPort := domainPortRegex.Match([]byte(v))
			isIPWithPort := ipPortRegex.Match([]byte(v))
			isException := slices.Contains(noProxyExceptions, v)

			if ip != nil || cidrErr == nil || isNoProxyDomain || isException || isDomainWithPort || isIPWithPort {
				continue
			}
			return fmt.Errorf("%s: %s is neither an IP, CIDR, domain, '*', domain:port, or IP:port", errMsg, v)
		}
		return nil
	}

	s, err := readString(label, defaultVal, validate, "")
	if err != nil {
		log.Debug("failure in ReadNoProxy: %v", err)
		return s, err
	}
	return s, nil
}

func ReadURL(label, defaultVal, errMsg string, isOptional bool) (string, error) {

	validate := func(input string) error {
		if input == "" {
			if !isOptional {
				return errors.New(errMsg)
			} else {
				return nil
			}
		}

		_, err := url.ParseRequestURI(input)
		if err != nil {
			return errors.New(errMsg)
		}

		u, err := url.Parse(input)
		if err != nil || u.Scheme == "" || u.Host == "" {
			return errors.New(errMsg)
		}
		return nil
	}

	s, err := readString(label, defaultVal, validate, "")
	if err != nil {
		log.Debug("failure in ReadURL: %v", err)
		return s, err
	}

	s = strings.TrimRight(s, "/")
	return s, nil
}

func ReadDomainOrIP(label, defaultVal, errMsg string, isOptional bool) (string, error) {

	validate := func(input string) error {
		if input == "" {
			if !isOptional {
				return errors.New(errMsg)
			} else {
				return nil
			}
		}

		ip := net.ParseIP(input)
		isIPWithPort := ipPortRegex.Match([]byte(input))
		isDomain := domainRegex.Match([]byte(input))
		if ip != nil || isIPWithPort || isDomain {
			return nil
		}
		return fmt.Errorf("%s: %s is neither an IP, IP:port, or an FQDN", errMsg, input)
	}

	s, err := readString(label, defaultVal, validate, "")
	if err != nil {
		log.Debug("failure in ReadDomainOrIP: %v", err)
		return s, err
	}
	return s, nil
}

func ReadDomains(label, defaultVal, errMsg string, isOptional bool, maxVals int) (string, error) {

	validate := func(input string) error {
		if input == "" {
			if !isOptional {
				return errors.New(errMsg)
			} else {
				return nil
			}
		}
		vals := strings.Split(input, ",")
		if maxVals > 0 && len(vals) > maxVals {
			return fmt.Errorf("%s: maximum domains: %d", errMsg, maxVals)
		}
		for _, v := range vals {
			if !domainRegex.Match([]byte(v)) {
				return errors.New(errMsg)
			}
		}
		return nil
	}

	s, err := readString(label, defaultVal, validate, "")
	if err != nil {
		log.Debug("failure in ReadDomains: %v", err)
		return s, err
	}
	return s, nil
}

func ReadIPs(label, defaultVal, errMsg string, isOptional bool, maxVals int) (string, error) {

	validate := func(input string) error {
		if input == "" {
			if !isOptional {
				return errors.New(errMsg)
			} else {
				return nil
			}
		}
		vals := strings.Split(input, ",")
		if maxVals > 0 && len(vals) > maxVals {
			return fmt.Errorf("%s: maximum IPs: %d", errMsg, maxVals)
		}
		for _, v := range vals {
			if ip := net.ParseIP(v); ip == nil {
				return errors.New(errMsg)
			}
		}
		return nil
	}

	s, err := readString(label, defaultVal, validate, "")
	if err != nil {
		log.Debug("failure in ReadIP: %v", err)
		return s, err
	}
	return s, nil
}

func ReadCIDRs(label, defaultVal, errMsg string, isOptional bool, maxVals int) (string, error) {

	validate := func(input string) error {
		if input == "" {
			if !isOptional {
				return errors.New(errMsg)
			} else {
				return nil
			}
		}
		vals := strings.Split(input, ",")
		if maxVals > 0 && len(vals) > maxVals {
			return fmt.Errorf("%s: maximum CIDRs: %d", errMsg, maxVals)
		}
		for _, v := range vals {
			if _, _, err := net.ParseCIDR(v); err != nil {
				return errors.New(errMsg)
			}
		}
		return nil
	}

	s, err := readString(label, defaultVal, validate, "")
	if err != nil {
		log.Debug("failure in ReadCIDRs: %v", err)
		return s, err
	}
	return s, nil
}

func ReadFilePath(label, defaultVal, errMsg string, isOptional bool) (string, error) {

	validate := func(input string) error {
		if input == "" {
			if !isOptional {
				return errors.New(errMsg)
			} else {
				return nil
			}
		}
		fileInfo, err := os.Stat(input)
		if err != nil {
			return err
		}
		if fileInfo.IsDir() {
			return fmt.Errorf("input %s is a directory, not a file", input)
		}
		return nil
	}

	s, err := readString(label, defaultVal, validate, "")
	if err != nil {
		log.Debug("failure in ReadFilePath: %v", err)
		return s, err
	}
	return s, nil
}

func ReadText(label, defaultVal, errMsg string, isOptional bool, maxLen int) (string, error) {
	s, err := readString(label, defaultVal, validateStringFunc(errMsg, isOptional, maxLen), "")
	if err != nil {
		return s, wrap_errors.Wrap(err, "failure in ReadText")
	}
	return strings.TrimSpace(s), nil
}

func ReadTextRegex(label, defaultVal, errMsg, regexPattern string) (string, error) {

	validate := func(input string) error {
		r, err := regexp.Compile(regexPattern)
		if err != nil {
			return err
		}
		m := r.Find([]byte(input))
		if string(m) == input {
			return nil
		}
		return fmt.Errorf("input %s does not match regex %s; %s", input, regexPattern, errMsg)
	}

	s, err := readString(label, defaultVal, validate, "")
	if err != nil {
		return s, wrap_errors.Wrap(err, "failure in ReadTextRegex")
	}
	return s, nil
}

func ReadPassword(label, defaultVal, errMsg string, isOptional bool, maxLen int) (string, error) {
	s, err := readString(label, defaultVal, validateStringFunc(errMsg, isOptional, maxLen), "*")
	if err != nil {
		return s, wrap_errors.Wrap(err, "failure in ReadPassword")
	}
	return s, nil
}

func ReadK8sName(label, defaultVal, errMsg string, isOptional bool) (string, error) {

	validate := func(input string) error {
		if err := validateStringFunc(errMsg, isOptional, -1)(input); err != nil {
			return err
		}
		if err := validateK8sName(input, isOptional); err != nil {
			return err
		}
		return nil
	}

	s, err := readString(label, defaultVal, validate, "")
	if err != nil {
		return s, wrap_errors.Wrap(err, "failure in ReadK8sName")
	}
	return s, nil
}

func ReadBool(label string, defaultVal bool) (bool, error) {

	defaultValStr := "N"
	if defaultVal {
		defaultValStr = "Y"
	}

	prompt := GetPrompter(label, defaultValStr, false, true, nil, nil)
	resultStr, err := prompt.Run()
	choice := strings.ToUpper(resultStr)

	if err != nil {
		if err.Error() == ctrlD {
			return ReadBool(label, defaultVal)
		}
		if err.Error() != "" {
			return false, wrap_errors.Wrap(err, "failure in ReadBool")
		}
		// prompt.Run() returns an empty error when isConfirm == true and "" (i.e., default) is entered
		if !slices.Contains([]string{"Y", "N", ""}, choice) {
			log.InfoCLI("Please enter either 'Y' or 'N'")
			return ReadBool(label, defaultVal)
		}
	}
	if choice == "" {
		choice = defaultValStr
	}
	return choice == "Y", nil
}

func ReadInt(label, defaultVal, errMsg string, minVal, maxVal int64) (int, error) {

	validate := func(input string) error {
		i, err := strconv.ParseInt(input, 10, 32)
		if err != nil {
			return wrap_errors.Wrap(err, errMsg)
		}
		if minVal > 0 && i < minVal || maxVal > 0 && i > maxVal {
			return errors.New(errMsg)
		}
		return nil
	}

	prompt := GetPrompter(label, defaultVal, true, false, validate, nil)
	resultStr, err := prompt.Run()
	if err != nil {
		if err.Error() == ctrlD {
			return ReadInt(label, defaultVal, errMsg, minVal, maxVal)
		}
		return -1, wrap_errors.Wrap(err, "failure in ReadInt")
	}
	result, err := strconv.ParseInt(resultStr, 10, 32)
	return int(result), err

}

func validateStringFunc(errMsg string, isOptional bool, maxLen int) func(input string) error {
	return func(input string) error {
		if !isOptional && input == "" {
			return errors.New(errMsg)
		}
		fieldLen := len(input)
		if maxLen > 0 && fieldLen > maxLen {
			return fmt.Errorf("maximum length of %d chars exceeded. input length: %d", maxLen, fieldLen)
		}
		return nil
	}
}

func readString(label, defaultVal string, validate func(input string) error, mask string) (string, error) {
	var m rune
	if mask != "" {
		m, _ = utf8.DecodeRuneInString(mask)
	}

	prompt := GetPrompter(label, defaultVal, false, false, validate, &m)
	resultStr, err := prompt.Run()
	if err != nil {
		if err.Error() == ctrlD {
			return readString(label, defaultVal, validate, mask)
		}
		return resultStr, err
	}
	return resultStr, err
}

func validateK8sName(name string, isOptional bool) error {
	if isOptional && name == "" {
		return nil
	}
	if errs := validation.IsQualifiedName(name); errs != nil {
		return errors.New(strings.Join(errs, ", "))
	}
	return nil
}

/*

Workaround for terminal bell chime sound when using select

*/

type noBellStdout struct{}

func (n *noBellStdout) Write(p []byte) (int, error) {
	if len(p) == 1 && p[0] == readline.CharBell {
		return 0, nil
	}
	return readline.Stdout.Write(p)
}

func (n *noBellStdout) Close() error {
	return readline.Stdout.Close()
}

var NoBellStdout = &noBellStdout{}
