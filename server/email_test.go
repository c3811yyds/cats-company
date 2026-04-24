package server

import (
	"strings"
	"testing"
)

func TestBuildTencentCloudAuthorizationMatchesOfficialExample(t *testing.T) {
	payload := `{"Limit": 1, "Filters": [{"Values": ["\u672a\u547d\u540d"], "Name": "instance-name"}]}`
	auth := buildTencentCloudAuthorization(
		"AKID********************************",
		"********************************",
		"cvm",
		"cvm.tencentcloudapi.com",
		"DescribeInstances",
		payload,
		1551113065,
	)

	const want = "Signature=10b1a37a7301a02ca19a647ad722d5e43b4b3cff309d421d85b46093f6ab6c4f"
	if !strings.Contains(auth, want) {
		t.Fatalf("authorization signature mismatch\nwant contains: %s\ngot: %s", want, auth)
	}
}
