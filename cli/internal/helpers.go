package internal

// StrPts is a helper function to return a pointer to a string
func StrPtr(s string) *string {

	return &s
}

// BoolPtr is a helper function to return a pointer to a bool
func BoolPtr(b bool) *bool {

	return &b
}
