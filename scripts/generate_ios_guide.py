import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import arabic_reshaper
from bidi.algorithm import get_display
import cv2
import imageio

import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

# ── Font Loading Helpers ──
FONT_PATH = "C:/Windows/Fonts/segoeui.ttf"
FONT_BOLD_PATH = "C:/Windows/Fonts/segoeuib.ttf"
TAHOMA_PATH = "C:/Windows/Fonts/tahoma.ttf"
TAHOMA_BOLD_PATH = "C:/Windows/Fonts/tahomabd.ttf"

def get_font(size, bold=False):
    try:
        path = TAHOMA_BOLD_PATH if bold else TAHOMA_PATH
        if not os.path.exists(path):
            path = FONT_BOLD_PATH if bold else FONT_PATH
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()

def ar(text):
    """Reshape and reorder Arabic text for proper RTL display."""
    if not text:
        return ""
    try:
        reshaped = arabic_reshaper.reshape(text)
        return get_display(reshaped)
    except Exception:
        return text

# ── Dimension Constants ──
W, H = 540, 960  # Crisp 9:16 portrait
FPS = 12
TOTAL_SECONDS = 13
TOTAL_FRAMES = FPS * TOTAL_SECONDS

# Colors
BG_DARK = (15, 23, 42)
PHONE_BORDER = (45, 55, 72)
PHONE_SCREEN_BG = (248, 250, 252)
ACCENT_BLUE = (0, 122, 255)
SUCCESS_GREEN = (52, 199, 89)
GOLD = (245, 158, 11)
CARD_BG = (255, 255, 255)
TEXT_DARK = (15, 23, 42)
TEXT_MUTED = (100, 116, 139)
BORDER_GRAY = (226, 232, 240)

# Load App Logo
LOGO_PATH = "assets/images/app_logo.png"
if not os.path.exists(LOGO_PATH):
    LOGO_PATH = "web/icons/Icon-192.png"

app_logo = None
if os.path.exists(LOGO_PATH):
    try:
        app_logo = Image.open(LOGO_PATH).convert("RGBA")
    except Exception:
        pass

def draw_dynamic_island_and_status(draw, w, h):
    # Dynamic Island
    di_w, di_h = 110, 26
    di_x = (w - di_w) // 2
    di_y = 12
    draw.rounded_rectangle([di_x, di_y, di_x + di_w, di_y + di_h], radius=13, fill=(0, 0, 0))
    # Camera dot
    draw.ellipse([di_x + di_w - 24, di_y + 7, di_x + di_w - 12, di_y + 19], fill=(20, 20, 25))

    # Status Bar: 9:41
    time_font = get_font(13, bold=True)
    draw.text((36, 16), "9:41", font=time_font, fill=(0, 0, 0))

    # Icons right (battery, wifi)
    bx, by = w - 55, 17
    draw.rounded_rectangle([bx, by, bx + 22, by + 11], radius=3, outline=(0, 0, 0), width=1)
    draw.rectangle([bx + 2, by + 2, bx + 16, by + 9], fill=(0, 0, 0))
    draw.rectangle([bx + 23, by + 4, bx + 24, by + 7], fill=(0, 0, 0))
    # Wifi waves
    draw.arc([bx - 18, by, bx - 6, by + 12], start=200, end=340, fill=(0, 0, 0), width=2)
    draw.arc([bx - 15, by + 3, bx - 9, by + 12], start=200, end=340, fill=(0, 0, 0), width=2)

def draw_top_step_indicator(draw, w, step_num, step_title_ar, step_title_en):
    # Header card above mockup or top of screen
    box_y = 52
    draw.rounded_rectangle([20, box_y, w - 20, box_y + 50], radius=12, fill=(241, 245, 249), outline=BORDER_GRAY)
    
    # Badge
    draw.rounded_rectangle([w - 110, box_y + 10, w - 30, box_y + 40], radius=8, fill=ACCENT_BLUE)
    badge_text = ar(f"خطوة {step_num}")
    f_badge = get_font(12, bold=True)
    draw.text((w - 92, box_y + 16), badge_text, font=f_badge, fill=(255, 255, 255))

    # Title
    f_title = get_font(13, bold=True)
    f_sub = get_font(10, bold=False)
    draw.text((32, box_y + 10), ar(step_title_ar), font=f_title, fill=TEXT_DARK)
    draw.text((32, box_y + 28), step_title_en, font=f_sub, fill=TEXT_MUTED)

def draw_finger_touch(draw, x, y, progress):
    """Animated circular ripple simulating finger tap."""
    # Radius expands as progress 0 -> 1
    r_core = 14
    draw.ellipse([x - r_core, y - r_core, x + r_core, y + r_core], fill=(0, 122, 255, 200), outline=(255, 255, 255), width=2)
    # Ripple ring
    r_ripple = int(r_core + 18 * progress)
    alpha = int(255 * (1.0 - progress))
    if alpha > 0:
        draw.ellipse([x - r_ripple, y - r_ripple, x + r_ripple, y + r_ripple], outline=(0, 122, 255, alpha), width=3)

def render_frame(frame_idx):
    # Base canvas
    img = Image.new("RGBA", (W, H), (250, 250, 252, 255))
    draw = ImageDraw.Draw(img)

    t = frame_idx / FPS  # Time in seconds

    # Always draw status bar
    draw_dynamic_island_and_status(draw, W, H)

    # ── SCENE 1: Safari Download Prompt (0.0s -> 3.2s) ──
    if t < 3.2:
        draw_top_step_indicator(draw, W, "1", "السماح بتحميل ملف التعريف", "Allow Profile Download (Safari)")

        # Safari Address Bar
        s_y = 118
        draw.rounded_rectangle([25, s_y, W - 25, s_y + 40], radius=10, fill=(235, 238, 242))
        f_url = get_font(12, bold=False)
        draw.text((40, s_y + 12), "🔒 mohadarati.vercel.app/api/mobileconfig", font=f_url, fill=TEXT_MUTED)

        # Webpage background placeholder
        draw.rounded_rectangle([25, s_y + 55, W - 25, 460], radius=16, fill=(255, 255, 255), outline=BORDER_GRAY)
        if app_logo:
            logo_s = app_logo.resize((70, 70))
            img.paste(logo_s, (W // 2 - 35, s_y + 85), logo_s)
        f_web = get_font(15, bold=True)
        web_title = ar("منصة محاضراتي - NUST")
        draw.text((W // 2 - 80, s_y + 165), web_title, font=f_web, fill=TEXT_DARK)

        # iOS Modal Alert Dialog
        alert_w, alert_h = 440, 220
        ax = (W - alert_w) // 2
        ay = 490

        # Modal shadow & background
        draw.rounded_rectangle([ax, ay, ax + alert_w, ay + alert_h], radius=18, fill=(255, 255, 255), outline=(203, 213, 225), width=2)

        f_alert_title = get_font(13, bold=True)
        f_alert_sub = get_font(11, bold=False)

        title_txt = ar("يحاول هذا الموقع تنزيل ملف تعريف تكوين.")
        title_txt2 = ar("هل ترغب في السماح بذلك؟")
        sub_txt = "This website is trying to download a configuration profile."
        sub_txt2 = "Do you want to allow this?"

        draw.text((W // 2 - 145, ay + 20), title_txt, font=f_alert_title, fill=TEXT_DARK)
        draw.text((W // 2 - 85, ay + 42), title_txt2, font=f_alert_title, fill=TEXT_DARK)
        draw.text((W // 2 - 165, ay + 72), sub_txt, font=f_alert_sub, fill=TEXT_MUTED)
        draw.text((W // 2 - 75, ay + 90), sub_txt2, font=f_alert_sub, fill=TEXT_MUTED)

        # Separator line
        draw.line([ax, ay + 135, ax + alert_w, ay + 135], fill=BORDER_GRAY, width=1)
        draw.line([W // 2, ay + 135, W // 2, ay + alert_h], fill=BORDER_GRAY, width=1)

        # Buttons
        f_btn = get_font(14, bold=True)
        # Left button: Ignore / إغلاق
        draw.text((ax + 75, ay + 155), ar("تجاهل"), font=f_btn, fill=(100, 116, 139))
        draw.text((ax + 70, ay + 178), "Ignore", font=get_font(11), fill=(100, 116, 139))

        # Right button: Allow / السماح (Target!)
        allow_bg = (235, 245, 255) if t > 1.8 else (255, 255, 255)
        draw.rounded_rectangle([W // 2 + 5, ay + 138, ax + alert_w - 5, ay + alert_h - 5], radius=12, fill=allow_bg)
        draw.text((W // 2 + 65, ay + 155), ar("السماح"), font=f_btn, fill=ACCENT_BLUE)
        draw.text((W // 2 + 70, ay + 178), "Allow", font=get_font(11, bold=True), fill=ACCENT_BLUE)

        # Touch animation moving to Allow button
        if 1.0 <= t < 3.0:
            touch_p = min(1.0, (t - 1.0) / 0.8)
            tx = int(W // 2 + 90)
            ty = int(ay + 170)
            draw_finger_touch(draw, tx, ty, (t * 2.5) % 1.0)

        # Bottom Confirmation Banner if clicked
        if t >= 2.2:
            banner_y = 740
            draw.rounded_rectangle([30, banner_y, W - 30, banner_y + 85], radius=14, fill=(240, 253, 244), outline=(134, 239, 172), width=2)
            f_b_bold = get_font(13, bold=True)
            f_b_sub = get_font(11, bold=False)
            draw.text((50, banner_y + 16), ar("✅ تم تنزيل ملف التعريف بنجاح!"), font=f_b_bold, fill=(22, 101, 52))
            draw.text((50, banner_y + 38), ar("افتح تطبيق الإعدادات للمتابعة والتثبيت"), font=f_b_sub, fill=(21, 128, 61))
            draw.text((50, banner_y + 56), "Profile Downloaded. Check Settings.", font=get_font(10), fill=(21, 128, 61))

    # ── SCENE 2: Settings App (3.2s -> 6.5s) ──
    elif t < 6.5:
        draw_top_step_indicator(draw, W, "2", "فتح الإعدادات والضغط على الملف", "Open Settings & Tap Downloaded Profile")

        # iOS Settings Header
        set_y = 118
        f_large = get_font(24, bold=True)
        draw.text((30, set_y), ar("الإعدادات"), font=f_large, fill=TEXT_DARK)
        draw.text((150, set_y + 8), "Settings", font=get_font(14), fill=TEXT_MUTED)

        # Apple ID Card
        aid_y = 165
        draw.rounded_rectangle([25, aid_y, W - 25, aid_y + 70], radius=14, fill=CARD_BG, outline=BORDER_GRAY)
        draw.ellipse([45, aid_y + 12, 90, aid_y + 57], fill=(203, 213, 225))
        draw.text((57, aid_y + 20), "🎓", font=get_font(18))
        draw.text((105, aid_y + 16), ar("طالب الكلية التقنية الهندسية"), font=get_font(13, bold=True), fill=TEXT_DARK)
        draw.text((105, aid_y + 38), "Apple Account, iCloud & Media", font=get_font(10), fill=TEXT_MUTED)

        # TARGET ROW: "تم تنزيل ملف التعريف" (Highlighted with pulsating glow!)
        row_y = 255
        glow = int(128 + 127 * math.sin((t - 3.2) * 5))
        pulse_border = (0, 122, 255, glow)
        draw.rounded_rectangle([25, row_y, W - 25, row_y + 78], radius=14, fill=(255, 255, 255), outline=ACCENT_BLUE, width=3)

        # Blue download icon inside row
        draw.rounded_rectangle([40, row_y + 16, 86, row_y + 62], radius=10, fill=ACCENT_BLUE)
        draw.text((54, row_y + 24), "📥", font=get_font(16))

        # Text labels
        f_row_t = get_font(14, bold=True)
        f_row_s = get_font(11, bold=False)
        draw.text((100, row_y + 18), ar("تم تنزيل ملف التعريف"), font=f_row_t, fill=TEXT_DARK)
        draw.text((100, row_y + 40), "Profile Downloaded  •  محاضراتي NUST", font=f_row_s, fill=ACCENT_BLUE)

        # Arrow indicator
        draw.text((W - 55, row_y + 28), "❯", font=get_font(16, bold=True), fill=ACCENT_BLUE)

        # Other standard Settings rows (Wi-Fi, Bluetooth) for realism
        for idx, (icon, name_ar, name_en) in enumerate([("📶", "شبكة Wi-Fi", "Wi-Fi"), ("🔵", "البلوتوث", "Bluetooth"), ("🔔", "الإشعارات", "Notifications")]):
            ry = 350 + idx * 56
            draw.rounded_rectangle([25, ry, W - 25, ry + 50], radius=10, fill=CARD_BG, outline=BORDER_GRAY)
            draw.text((45, ry + 14), icon, font=get_font(14))
            draw.text((80, ry + 14), ar(name_ar), font=get_font(12, bold=True), fill=TEXT_DARK)
            draw.text((200, ry + 15), name_en, font=get_font(11), fill=TEXT_MUTED)
            draw.text((W - 50, ry + 14), "❯", font=get_font(12), fill=TEXT_MUTED)

        # Animated finger tap pressing "تم تنزيل ملف التعريف"
        if t >= 4.2:
            tx = W // 2
            ty = row_y + 39
            draw_finger_touch(draw, tx, ty, ((t - 4.2) * 2.5) % 1.0)

    # ── SCENE 3: Profile Install & Passcode (6.5s -> 10.2s) ──
    elif t < 10.2:
        draw_top_step_indicator(draw, W, "3", "تثبيت الملف وإدخال رمز القفل", "Tap Install & Enter Passcode")

        # Top Navigation Bar
        nav_y = 118
        draw.rectangle([0, nav_y, W, nav_y + 45], fill=(248, 250, 252))
        draw.line([0, nav_y + 45, W, nav_y + 45], fill=BORDER_GRAY, width=1)
        draw.text((25, nav_y + 12), ar("إلغاء / Cancel"), font=get_font(12), fill=TEXT_MUTED)
        draw.text((W // 2 - 60, nav_y + 12), ar("تثبيت ملف التعريف"), font=get_font(13, bold=True), fill=TEXT_DARK)

        # Top-Right Blue "Install / تثبيت" button (Target 1)
        btn_hl = t < 8.2
        btn_bg = (220, 238, 255) if (t > 7.2 and t < 8.2) else (240, 245, 255)
        draw.rounded_rectangle([W - 130, nav_y + 6, W - 15, nav_y + 38], radius=8, fill=btn_bg, outline=ACCENT_BLUE)
        draw.text((W - 118, nav_y + 12), ar("تثبيت / Install"), font=get_font(11, bold=True), fill=ACCENT_BLUE)

        # Profile Card
        card_y = 180
        draw.rounded_rectangle([25, card_y, W - 25, card_y + 150], radius=16, fill=CARD_BG, outline=BORDER_GRAY)
        if app_logo:
            logo_s = app_logo.resize((60, 60))
            img.paste(logo_s, (45, card_y + 20), logo_s)

        draw.text((120, card_y + 20), ar("محاضراتي - NUST"), font=get_font(15, bold=True), fill=TEXT_DARK)
        draw.text((120, card_y + 45), ar("الكلية التقنية الهندسية"), font=get_font(11), fill=TEXT_MUTED)
        draw.text((120, card_y + 65), "National University of Science & Tech", font=get_font(10), fill=TEXT_MUTED)
        draw.text((45, card_y + 105), ar("تم التحقق منها ✔️ (Verified) • تطبيق ويب مستقل"), font=get_font(11, bold=True), fill=SUCCESS_GREEN)

        # Sub-stage: Passcode input screen (8.2s -> 10.2s)
        if t >= 8.2:
            # Darkened overlay or Passcode dialog
            pad_y = 360
            draw.rounded_rectangle([30, pad_y, W - 30, pad_y + 380], radius=20, fill=(255, 255, 255), outline=ACCENT_BLUE, width=2)

            f_pass_t = get_font(15, bold=True)
            draw.text((W // 2 - 75, pad_y + 20), ar("أدخل رمز الدخول"), font=f_pass_t, fill=TEXT_DARK)
            draw.text((W // 2 - 60, pad_y + 45), "Enter Passcode", font=get_font(12), fill=TEXT_MUTED)

            # Subtitle explanation: Your phone passcode!
            draw.rounded_rectangle([50, pad_y + 75, W - 50, pad_y + 115], radius=10, fill=(241, 245, 249))
            draw.text((W // 2 - 130, pad_y + 85), ar("🔒 أدخل رمز قفل الشاشة الخاص بهاتفك"), font=get_font(11, bold=True), fill=TEXT_DARK)

            # 4 Passcode Dots animating
            dots_y = pad_y + 135
            progress_dots = int((t - 8.2) * 2.5)  # fills 0, 1, 2, 3, 4
            for i in range(4):
                dx = W // 2 - 60 + i * 40
                if i < progress_dots:
                    draw.ellipse([dx, dots_y, dx + 16, dots_y + 16], fill=TEXT_DARK)
                else:
                    draw.ellipse([dx, dots_y, dx + 16, dots_y + 16], outline=TEXT_MUTED, width=2)

            # Bottom Final Confirmation Button
            if t >= 9.2:
                btn_final_y = pad_y + 180
                draw.rounded_rectangle([50, btn_final_y, W - 50, btn_final_y + 55], radius=14, fill=ACCENT_BLUE)
                draw.text((W // 2 - 75, btn_final_y + 16), ar("تأكيد التثبيت (Install)"), font=get_font(13, bold=True), fill=(255, 255, 255))
                # Finger tap on final confirm
                draw_finger_touch(draw, W // 2, btn_final_y + 27, ((t - 9.2) * 3) % 1.0)
        else:
            # Finger tap on top-right Install button
            tx = W - 70
            ty = nav_y + 22
            draw_finger_touch(draw, tx, ty, ((t - 6.5) * 2.5) % 1.0)

    # ── SCENE 4: Done! App Installed on Home Screen (10.2s -> 13.0s) ──
    else:
        draw_top_step_indicator(draw, W, "4", "تم التثبيت بنجاح!", "Success! Installed on Home Screen")

        # iPhone Home Screen Mockup (Beautiful deep gradient background)
        hs_y = 118
        draw.rounded_rectangle([15, hs_y, W - 15, H - 30], radius=24, fill=(15, 23, 42))

        # Grid of sample iOS apps (Messages, Safari, Camera, Photos)
        row1_y = hs_y + 40
        app_names = [("رسائل", "💬"), ("سفاري", "🧭"), ("صور", "🖼️"), ("كاميرا", "📷")]
        for idx, (aname, aicon) in enumerate(app_names):
            ax = 45 + idx * 125
            draw.rounded_rectangle([ax, row1_y, ax + 64, row1_y + 64], radius=14, fill=(30, 41, 59))
            draw.text((ax + 18, row1_y + 16), aicon, font=get_font(18))
            draw.text((ax + 12, row1_y + 72), ar(aname), font=get_font(10), fill=(203, 213, 225))

        # ROW 2: OUR APP! (محاضراتي) WITH SPECIAL CELEBRATION GLOW
        row2_y = row1_y + 115
        app_x = 45

        # Glowing ring
        glow_r = int(45 + 8 * math.sin((t - 10.2) * 6))
        draw.ellipse([app_x + 32 - glow_r, row2_y + 32 - glow_r, app_x + 32 + glow_r, row2_y + 32 + glow_r], outline=GOLD, width=3)

        # Real App Icon
        if app_logo:
            logo_real = app_logo.resize((68, 68))
            img.paste(logo_real, (app_x, row2_y), logo_real)
        else:
            draw.rounded_rectangle([app_x, row2_y, app_x + 68, row2_y + 68], radius=16, fill=(14, 165, 233))
            draw.text((app_x + 18, row2_y + 18), "🎓", font=get_font(22))

        # Golden star badge
        draw.ellipse([app_x + 50, row2_y - 6, app_x + 72, row2_y + 16], fill=GOLD)
        draw.text((app_x + 55, row2_y - 4), "★", font=get_font(11, bold=True), fill=(0, 0, 0))

        # App Label under icon
        draw.text((app_x + 5, row2_y + 76), ar("محاضراتي"), font=get_font(12, bold=True), fill=(255, 255, 255))
        draw.text((app_x + 8, row2_y + 94), "NUST", font=get_font(10, bold=True), fill=GOLD)

        # Big Celebratory Card at Bottom
        card_suc_y = row2_y + 140
        draw.rounded_rectangle([35, card_suc_y, W - 35, card_suc_y + 140], radius=18, fill=(240, 253, 244), outline=(74, 222, 128), width=2)

        f_suc_t = get_font(16, bold=True)
        draw.text((W // 2 - 105, card_suc_y + 18), ar("🎉 مبروك! تم التثبيت بنجاح"), font=f_suc_t, fill=(22, 101, 52))
        draw.text((W // 2 - 100, card_suc_y + 48), "App Installed on iPhone", font=get_font(12, bold=True), fill=(21, 128, 61))

        draw.line([50, card_suc_y + 75, W - 50, card_suc_y + 75], fill=(187, 247, 208), width=1)
        draw.text((W // 2 - 145, card_suc_y + 88), ar("التطبيق يفتح بملء الشاشة ويتحدث تلقائياً"), font=get_font(11, bold=True), fill=TEXT_DARK)
        draw.text((W // 2 - 105, card_suc_y + 110), ar("بدون الحاجة لمتجر آب ستور"), font=get_font(10), fill=TEXT_MUTED)

    # Convert to RGB numpy array for video/gif
    return np.array(img.convert("RGB"))

def main():
    print(f"[INFO] Generating {TOTAL_FRAMES} frames ({TOTAL_SECONDS}s @ {FPS}fps)...")
    frames = []
    
    for i in range(TOTAL_FRAMES):
        frame = render_frame(i)
        frames.append(frame)
        if (i + 1) % 24 == 0 or i == TOTAL_FRAMES - 1:
            print(f"  Frame {i + 1}/{TOTAL_FRAMES} rendered ({int((i + 1) / TOTAL_FRAMES * 100)}%)")

    # Output paths
    os.makedirs("web", exist_ok=True)
    gif_path = "web/ios_install_guide.gif"
    mp4_path = "web/ios_install_guide.mp4"

    # Save GIF
    print(f"[INFO] Saving GIF to {gif_path}...")
    imageio.mimsave(gif_path, frames, fps=FPS, loop=0)
    print(f"[SUCCESS] GIF saved ({os.path.getsize(gif_path) / 1024:.1f} KB)")

    # Save MP4
    print(f"[INFO] Saving MP4 to {mp4_path}...")
    h, w, _ = frames[0].shape
    writer = cv2.VideoWriter(mp4_path, cv2.VideoWriter_fourcc(*'mp4v'), FPS, (w, h))
    for f in frames:
        writer.write(cv2.cvtColor(f, cv2.COLOR_RGB2BGR))
    writer.release()
    print(f"[SUCCESS] MP4 saved ({os.path.getsize(mp4_path) / 1024:.1f} KB)")

if __name__ == "__main__":
    main()
