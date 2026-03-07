import urllib.request
import json

supabase_url = "https://qlarqavoqhkuwzmevrmf.supabase.co"
anon_key = "sb_publishable_7zM8XNRg-rv-pPBQFQDU0g_4TnOjtQQ"

auth_url = f"{supabase_url}/auth/v1/signup"
req_auth = urllib.request.Request(auth_url, method="POST", data=b"{}")
req_auth.add_header("Content-Type", "application/json")
req_auth.add_header("apikey", anon_key)
auth_data = json.loads(urllib.request.urlopen(req_auth).read().decode())
token = auth_data["access_token"]

edge_url = f"{supabase_url}/functions/v1/identify"
payload = json.dumps({"geminiFileUri": "test_auth_edge", "gpsLatitude": 0, "gpsLongitude": 0}).encode("utf-8")
req_edge = urllib.request.Request(edge_url, method="POST", data=payload)
req_edge.add_header("Content-Type", "application/json")
req_edge.add_header("Authorization", f"Bearer {token}")
try:
    resp = urllib.request.urlopen(req_edge)
    print("SUCCESS")
    print(resp.read().decode())
except urllib.error.HTTPError as e:
    print("ERROR")
    print(e.read().decode())
