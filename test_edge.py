import urllib.request
import json

supabase_url = "https://qlarqavoqhkuwzmevrmf.supabase.co"
anon_key = "sb_publishable_7zM8XNRg-rv-pPBQFQDU0g_4TnOjtQQ"

print("1. Attempting Anonymous Sign-In...")
auth_url = f"{supabase_url}/auth/v1/signup"
req_auth = urllib.request.Request(auth_url, method="POST", data=b"{}")
req_auth.add_header("Content-Type", "application/json")
req_auth.add_header("apikey", anon_key)

try:
    auth_resp = urllib.request.urlopen(req_auth)
    auth_data = json.loads(auth_resp.read().decode())
    user_id = auth_data.get("user", {}).get("id")
    access_token = auth_data.get("access_token")
    print(f"✅ SUCCESS. User ID: {user_id}")
    
    print("\n2. Pinging Identify Edge Function...")
    edge_url = f"{supabase_url}/functions/v1/identify"
    
    payload = json.dumps({
        "geminiFileUri": "test_uri",
        "gpsLatitude": 37.7749,
        "gpsLongitude": -122.4194,
        "depthScaleText": "1.2 meters",
        "weatherCondition": "Sunny"
    }).encode("utf-8")
    
    req_edge = urllib.request.Request(edge_url, method="POST", data=payload)
    req_edge.add_header("Content-Type", "application/json")
    req_edge.add_header("Authorization", f"Bearer {access_token}")
    
    edge_resp = urllib.request.urlopen(req_edge)
    print(f"✅ Edge SUCCESS: {edge_resp.status}")
    print(edge_resp.read().decode())
    
except urllib.error.HTTPError as e:
    print(f"❌ HTTP ERROR: {e.code}")
    print(e.read().decode())
except Exception as e:
    print(f"❌ FAILED: {str(e)}")
