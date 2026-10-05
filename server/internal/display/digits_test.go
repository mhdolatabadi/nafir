package display

import "testing"

func TestPersianDigits(t *testing.T) {
	for input, want := range map[string]string{
		"0123456789": "۰۱۲۳۴۵۶۷۸۹",
		"٠١٢٣٤٥٦٧٨٩": "۰۱۲۳۴۵۶۷۸۹",
		"۰۱:23": "۰۱:۲۳",
	} {
		if got := PersianDigits(input); got != want {
			t.Fatalf("got %q, want %q", got, want)
		}
	}
}
