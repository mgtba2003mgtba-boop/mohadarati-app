module.exports = async (req, res) => {
  const host = req.headers['x-forwarded-host'] || req.headers.host || 'mohadarati.vercel.app';
  const proto = req.headers['x-forwarded-proto'] || 'https';
  const fullUrl = `${proto}://${host}/`;

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.apple.webClip.managed</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadIdentifier</key>
            <string>com.nust.mohadarati.webclip</string>
            <key>PayloadUUID</key>
            <string>B6D953E2-7489-4D66-8806-C9E57BCDF678</string>
            <key>PayloadDisplayName</key>
            <string>محاضراتي</string>
            <key>PayloadDescription</key>
            <string>تطبيق محاضراتي - الكلية التقنية الهندسية NUST</string>
            <key>PayloadOrganization</key>
            <string>NUST Engineering College</string>
            <key>Label</key>
            <string>محاضراتي</string>
            <key>URL</key>
            <string>${fullUrl}</string>
            <key>IsRemovable</key>
            <true/>
            <key>FullScreen</key>
            <true/>
            <key>Precomposed</key>
            <true/>
            <key>Icon</key>
            <data>
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
            </data>
        </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>محاضراتي - NUST Portal</string>
    <key>PayloadIdentifier</key>
    <string>com.nust.mohadarati.profile</string>
    <key>PayloadOrganization</key>
    <string>الجامعة الوطنية للعلوم والتكنولوجيا</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>C5E98B4A-637A-4D78-9B21-E37D5BA6F590</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadDescription</key>
    <string>ملف تثبيت تطبيق محاضراتي المباشر لأجهزة الآيفون (iOS)</string>
</dict>
</plist>`;

  res.setHeader('Content-Type', 'application/x-apple-aspen-config');
  res.setHeader('Content-Disposition', 'attachment; filename="mohadarati.mobileconfig"');
  res.setHeader('Cache-Control', 'no-cache');
  return res.status(200).send(xml);
};
