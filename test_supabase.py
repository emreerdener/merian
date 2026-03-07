import urllib.request
import json

supabase_url = "https://qlarqavoqhkuwzmevrmf.supabase.co"
anon_key = "sb_publishable_aDnil93dDs__ROKq53b_0A_LHe77Os-"
url = f"{supabase_url}/functions/v1/identify"
req = urllib.request.Request(url, method="POST")
req.add_header("Content-Type", "application/json")
req.add_header("Authorization", f"Bearer {anon_key}")

payload = {
    "geminiFileUri": "https://generativelanguage.googleapis.com/v1beta/files/882ofxho7olf",
    "mimeType": "image/jpeg"
}
try:
    resp = urllib.request.urlopen(req, data=json.dumps(payload).encode())
    print(resp.read().decode())
except Exception as e:
    print(e)
    if hasattr(e, 'read'):
        print(e.read().decode())
