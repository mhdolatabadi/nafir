package main

import (
	"os"
	"strconv"
	"strings"
	"testing"
)

// The product limit is 1 GiB per account, and a deployment that doesn't
// set STORAGE_QUOTA_BYTES gets the same limit whichever default applies.
func TestDefaultStorageQuotaIsOneGiB(t *testing.T) {
	if defaultOwnerQuota != 1<<30 {
		t.Fatalf("default quota = %d bytes", defaultOwnerQuota)
	}
	want := strconv.FormatInt(defaultOwnerQuota, 10)
	for file, setting := range map[string]string{
		"../../../deploy/compose.yaml": "STORAGE_QUOTA_BYTES: ${STORAGE_QUOTA_BYTES:-" + want + "}",
		"../../../deploy/.env.example": "STORAGE_QUOTA_BYTES=" + want + "\n",
	} {
		content, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(string(content), setting) {
			t.Errorf("%s does not default the quota to %s bytes", file, want)
		}
	}

	t.Setenv("STORAGE_QUOTA_BYTES", "")
	if got, err := positiveInt64Env("STORAGE_QUOTA_BYTES", defaultOwnerQuota); err != nil || got != 1<<30 {
		t.Fatalf("unset quota = %d %v", got, err)
	}
}
