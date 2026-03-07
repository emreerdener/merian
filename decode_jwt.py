import urllib.request
import json
import base64

supabase_url = "https://qlarqavoqhkuwzmevrmf.supabase.co"
anon_key = "sb_publishable_aDnil93dDs__ROKq53b_0A_LHe77Os-"

auth_url = f"{supabase_url}/auth/v1/signup"
req_auth = urllib.request.Request(auth_url, method="POST")
req_auth.add_header("Content-Type", "application/json")
req_auth.add_header("apikey", anon_key)

try:
    resp_auth = urllib.request.urlopen(req_auth, data=b"{}")
    auth_data = json.loads(resp_auth.read().decode())
    jwt = auth_data.get("access_token")
    if jwt:
        parts = jwt.split('.')
        payload = json.loads(base64.urlsafe_b64decode(parts[1] + "===").decode())
        print(f"JWT Payload: {json.dumps(payload, indent=2)}")
except Exception as e:
    print(e)
