import os
import json
import base64
import io
from PIL import Image

SOURCE_IMAGE_PATH = r"C:/Users/Almustaqbal/.gemini/antigravity/brain/bfc00863-723c-4025-b49e-8dd823d96abb/.user_uploaded/media_1791918268156_5d3de2c2.jpg"
WORKSPACE_DIR = r"c:/Users/Almustaqbal/Downloads/تطبيق الحضور"

def make_padded_icon(source_img, size, seal_ratio=0.84):
    """
    Creates a clean square icon with pure white background and centered circular seal
    with safe margin to protect outer text from squircle/circle masks.
    """
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    seal_size = int(size * seal_ratio)
    resized_seal = source_img.resize((seal_size, seal_size), Image.Resampling.LANCZOS)
    
    offset = ((size - seal_size) // 2, (size - seal_size) // 2)
    # Paste resized seal onto canvas
    if resized_seal.mode == "RGBA":
        canvas.paste(resized_seal, offset, resized_seal)
    else:
        canvas.paste(resized_seal, offset)
    return canvas

def main():
    print(f"Loading source image from: {SOURCE_IMAGE_PATH}")
    src = Image.open(SOURCE_IMAGE_PATH).convert("RGBA")

    # 1. Web Icons
    web_icons_dir = os.path.join(WORKSPACE_DIR, "web", "icons")
    os.makedirs(web_icons_dir, exist_ok=True)

    print("Generating web PWA icons...")
    make_padded_icon(src, 192, 0.84).save(os.path.join(web_icons_dir, "Icon-192.png"), format="PNG")
    make_padded_icon(src, 512, 0.84).save(os.path.join(web_icons_dir, "Icon-512.png"), format="PNG")
    make_padded_icon(src, 192, 0.78).save(os.path.join(web_icons_dir, "Icon-maskable-192.png"), format="PNG")
    make_padded_icon(src, 512, 0.78).save(os.path.join(web_icons_dir, "Icon-maskable-512.png"), format="PNG")

    # 2. Favicon
    print("Generating web/favicon.png...")
    make_padded_icon(src, 128, 0.84).save(os.path.join(WORKSPACE_DIR, "web", "favicon.png"), format="PNG")

    # 3. Assets Images
    assets_dir = os.path.join(WORKSPACE_DIR, "assets", "images")
    os.makedirs(assets_dir, exist_ok=True)
    print("Generating assets/images/app_logo.png...")
    make_padded_icon(src, 512, 0.84).save(os.path.join(assets_dir, "app_logo.png"), format="PNG")

    # 4. Android Mipmaps
    android_res_dir = os.path.join(WORKSPACE_DIR, "android", "app", "src", "main", "res")
    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, dim in android_sizes.items():
        folder_path = os.path.join(android_res_dir, folder)
        if os.path.exists(folder_path):
            print(f"Generating Android icon for {folder} ({dim}x{dim})...")
            make_padded_icon(src, dim, 0.84).save(os.path.join(folder_path, "ic_launcher.png"), format="PNG")

    # 5. iOS AppIcon Set
    ios_icon_dir = os.path.join(WORKSPACE_DIR, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    contents_path = os.path.join(ios_icon_dir, "Contents.json")
    if os.path.exists(contents_path):
        with open(contents_path, "r", encoding="utf-8") as f:
            contents = json.load(f)
        print("Generating iOS AppIcon set...")
        for item in contents.get("images", []):
            filename = item.get("filename")
            size_str = item.get("size", "0x0")
            scale_str = item.get("scale", "1x")
            if filename:
                base_w, base_h = [float(x) for x in size_str.split("x")]
                scale = float(scale_str.replace("x", ""))
                pixel_dim = int(round(base_w * scale))
                target_path = os.path.join(ios_icon_dir, filename)
                make_padded_icon(src, pixel_dim, 0.84).save(target_path, format="PNG")
                print(f"  -> Generated {filename} ({pixel_dim}x{pixel_dim})")

    # 6. Base64 icon for Apple MobileConfig
    print("Generating Base64 icon for iOS mobileconfig...")
    buf = io.BytesIO()
    # 192x192 high-res icon for WebClip
    make_padded_icon(src, 192, 0.84).save(buf, format="PNG", optimize=True)
    b64_str = base64.b64encode(buf.getvalue()).decode("utf-8")

    # Update web/mohadarati.mobileconfig
    mobileconfig_path = os.path.join(WORKSPACE_DIR, "web", "mohadarati.mobileconfig")
    if os.path.exists(mobileconfig_path):
        with open(mobileconfig_path, "r", encoding="utf-8") as f:
            content = f.read()
        import re
        content = re.sub(r"<key>Icon</key>\s*<data>[\s\S]*?</data>", f"<key>Icon</key>\n            <data>\n{b64_str}\n            </data>", content)
        with open(mobileconfig_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("Updated web/mohadarati.mobileconfig successfully.")

    # Update web/api/mobileconfig.js
    mobileconfig_js_path = os.path.join(WORKSPACE_DIR, "web", "api", "mobileconfig.js")
    if os.path.exists(mobileconfig_js_path):
        with open(mobileconfig_js_path, "r", encoding="utf-8") as f:
            content_js = f.read()
        import re
        content_js = re.sub(r"<key>Icon</key>\s*<data>[\s\S]*?</data>", f"<key>Icon</key>\n            <data>\n{b64_str}\n            </data>", content_js)
        with open(mobileconfig_js_path, "w", encoding="utf-8") as f:
            f.write(content_js)
        print("Updated web/api/mobileconfig.js successfully.")

    print("All icons generated and integrated successfully!")

if __name__ == "__main__":
    main()
