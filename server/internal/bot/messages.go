package bot

import "fmt"

// Everything the bots say, in one place.
const (
	msgWelcome     = "سلام! این ربات نفیر است. فایل‌های صوتی را اینجا بفرستید تا به کتابخانهٔ نفیر شما اضافه شوند.\n\n" + msgHowToLink
	msgHowToLink   = "برای اتصال حساب نفیر: در اپ نفیر به «تنظیمات ← اتصال به بات» بروید، «دریافت کد» را بزنید و کد ۸ رقمی را همین‌جا بفرستید."
	msgBadCode     = "این کد درست نیست یا منقضی شده است. از اپ نفیر کد تازه بگیرید و دوباره بفرستید."
	msgLocked      = "چند بار کد اشتباه فرستاده‌اید. یک ساعت دیگر دوباره امتحان کنید."
	msgUnlinked    = "اتصال این گفتگو به حساب نفیر قطع شد. برای اتصال دوباره، از اپ نفیر کد تازه بگیرید."
	msgNotLinked   = "این گفتگو هنوز به حساب نفیر وصل نیست.\n\n" + msgHowToLink
	msgPrivateOnly = "ربات نفیر فقط در گفتگوی خصوصی کار می‌کند."
	msgHelp        = "فایل صوتی (mp3، m4a، flac، ogg، wav و …) بفرستید تا به کتابخانهٔ نفیر اضافه شود.\n\n" +
		"/status حساب متصل\n/logout قطع اتصال\n/help همین راهنما\n\n" + msgHowToLink
	msgTryAgain  = "مشکلی پیش آمد. کمی بعد دوباره امتحان کنید."
	msgSendAudio = "فایل صوتی بفرستید، یا /help را ببینید."
	msgQueued    = "فایل دریافت شد و در حال اضافه شدن به کتابخانه است…"
)

func msgLinked(email string) string {
	return fmt.Sprintf("این گفتگو به حساب %s وصل شد. حالا فایل صوتی بفرستید.", email)
}

func msgStatus(email string) string {
	return fmt.Sprintf("این گفتگو به حساب %s وصل است. فایل‌های صوتی که می‌فرستید به کتابخانهٔ همین حساب اضافه می‌شوند.", email)
}

func msgImported(title string) string {
	return fmt.Sprintf("«%s» به کتابخانهٔ نفیر اضافه شد.", title)
}

func msgRefused(reason string, maxMB int64) string {
	switch reason {
	case ReasonUnsupported:
		return "این فایل پشتیبانی نمی‌شود. فایل صوتی mp3، m4a، aac، flac، ogg، opus، wav یا webm بفرستید."
	case ReasonTooLarge:
		return fmt.Sprintf("حجم فایل بیشتر از %d مگابایت است و از طریق ربات قابل دریافت نیست.", maxMB)
	case ReasonQuota:
		return "فضای کتابخانهٔ شما پر است. برای افزودن آهنگ تازه، چند آهنگ را از کتابخانه حذف کنید."
	case ReasonPending:
		return "چند فایل در حال اضافه شدن است. صبر کنید تمام شوند و دوباره بفرستید."
	case ReasonDisabled:
		return "افزودن آهنگ فعلاً غیرفعال است. کمی بعد دوباره امتحان کنید."
	case ReasonInvalid:
		return "محتوای این فایل با قالبش جور نیست یا فایل صوتی سالمی نیست."
	default:
		return "افزودن این فایل ناموفق بود. دوباره بفرستید."
	}
}
