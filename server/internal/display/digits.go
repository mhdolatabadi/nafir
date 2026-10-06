// Package display formats user-facing values without changing protocol data.
package display

import "fmt"

func PersianDigits(value any) string {
	text := []rune(fmt.Sprint(value))
	for i, r := range text {
		if r >= '0' && r <= '9' {
			text[i] = '۰' + r - '0'
		}
		if r >= '٠' && r <= '٩' {
			text[i] = '۰' + r - '٠'
		}
	}
	return string(text)
}
