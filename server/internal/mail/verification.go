package mail

import (
	"html"

	"github.com/mhdolatabadi/nafir/server/internal/display"
)

// VerificationCode is the Persian email that carries an account's code.
func VerificationCode(to, code string, validMinutes int) Message {
	minutes := display.PersianDigits(validMinutes)
	text := "سلام،\n\n" +
		"کد تأیید ایمیل شما در ریتمو:\n\n" +
		code + "\n\n" +
		"این کد تا " + minutes + " دقیقه معتبر است. آن را در برنامه وارد کنید.\n" +
		"اگر شما در ریتمو ثبت‌نام نکرده‌اید، این ایمیل را نادیده بگیرید.\n\n" +
		"ریتمو\n"
	page := `<!doctype html>
<html lang="fa" dir="rtl">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>کد تأیید ریتمو</title></head>
<body dir="rtl" style="margin:0;padding:24px;background:#0b0d12;color:#eef0f5;font-family:Vazirmatn,Tahoma,sans-serif;text-align:right">
<div style="max-width:480px;margin:0 auto;padding:24px;border-radius:20px;background:#161a23">
<p style="margin:0 0 16px">سلام،</p>
<p style="margin:0 0 16px">کد تأیید ایمیل شما در ریتمو:</p>
<p dir="ltr" style="margin:0 0 16px;font-size:32px;font-weight:700;letter-spacing:8px;text-align:center">` + html.EscapeString(code) + `</p>
<p style="margin:0 0 8px">این کد تا ` + minutes + ` دقیقه معتبر است. آن را در برنامه وارد کنید.</p>
<p style="margin:0;color:#a9afbd">اگر شما در ریتمو ثبت‌نام نکرده‌اید، این ایمیل را نادیده بگیرید.</p>
</div>
</body>
</html>
`
	return Message{To: to, Subject: "کد تأیید ایمیل ریتمو", Text: text, HTML: page}
}
