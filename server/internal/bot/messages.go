package bot

import "fmt"

// Everything the bots say, in one place.
const (
	msgWelcome = "سلام! این ربات نفیر است. فایل‌های صوتی را اینجا بفرستید تا به کتابخانهٔ نفیر شما اضافه شوند.\n\n" +
		"برای شروع، ایمیل حساب نفیرتان را بفرستید. یک کد ورود به آن ایمیل می‌فرستیم؛ رمز عبورتان را هیچ‌وقت اینجا نفرستید."
	msgAskEmail    = "ایمیل حساب نفیرتان را بفرستید."
	msgBadEmail    = "این ایمیل معتبر نیست. دوباره بفرستید، مثلاً name@example.com"
	msgCodeSent    = "اگر حسابی با این ایمیل وجود داشته باشد، یک کد ۶ رقمی به آن فرستادیم. کد را همین‌جا بفرستید.\n\nکد نرسید؟ پوشهٔ اسپم را ببینید یا با /login دوباره امتحان کنید."
	msgThrottled   = "تعداد درخواست کد زیاد بوده است. کمی بعد دوباره امتحان کنید."
	msgBadCode     = "کد درست نیست یا منقضی شده است. دوباره بفرستید، یا با /login کد تازه بگیرید."
	msgSignedOut   = "از حساب نفیر خارج شدید. برای ورود دوباره /login را بفرستید."
	msgNotSignedIn = "اول وارد حساب نفیر شوید: /login"
	msgPrivateOnly = "ربات نفیر فقط در گفتگوی خصوصی کار می‌کند."
	msgHelp        = "فایل صوتی (mp3، m4a، flac، ogg، wav و …) بفرستید تا به کتابخانهٔ نفیر اضافه شود.\n\n" +
		"/login ورود با کد ایمیلی\n/status وضعیت حساب\n/logout خروج از حساب\n/help همین راهنما"
	msgTryAgain  = "مشکلی پیش آمد. کمی بعد دوباره امتحان کنید."
	msgSendAudio = "فایل صوتی بفرستید، یا /help را ببینید."
	msgQueued    = "فایل دریافت شد و در حال اضافه شدن به کتابخانه است…"
)

func msgWait(seconds int) string {
	return fmt.Sprintf("کد قبلی همین الان فرستاده شد. %d ثانیهٔ دیگر دوباره امتحان کنید.", seconds)
}

func msgSignedIn(email string) string {
	return fmt.Sprintf("با حساب %s وارد شدید. حالا فایل صوتی بفرستید.", email)
}

func msgStatus(email string) string {
	return fmt.Sprintf("با حساب %s وارد شده‌اید. فایل‌های صوتی که می‌فرستید به کتابخانهٔ همین حساب اضافه می‌شوند.", email)
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
