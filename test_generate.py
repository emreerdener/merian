import urllib.request
import json

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
except Exception as e:
    print(f"Auth Failed: {e}")
    exit(1)

edge_url = f"{supabase_url}/functions/v1/generate-upload-urls"
req_edge = urllib.request.Request(edge_url, method="POST")
req_edge.add_header("Content-Type", "application/json")
req_edge.add_header("Authorization", f"Bearer {jwt}")
req_edge.add_header("apikey", anon_key)

try:
    resp_edge = urllib.request.urlopen(req_edge, data=json.dumps({
        "userId": "1770f03e-c3c5-4441-90a9-1dc3b990648c",
        "imageCount": 1
    }).encode())
    print("\n✅ SUCCESS!")
    print(resp_edge.read().decode())
except Exception as e:
    print(f"\n❌ Failed: {e}")
    if hasattr(e, 'read'): print(e.read().decode())
