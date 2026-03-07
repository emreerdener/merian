import urllib.request
import json
import os

supabase_url = "https://qlarqavoqhkuwzmevrmf.supabase.co"
anon_key = "sb_publishable_aDnil93dDs__ROKq53b_0A_LHe77Os-"
gemini_key = "AIzaSyA4cvLnPE4g4hiwxVKc1N5H0djw3_WEXQc"

print("1. Generating Anonymous User JWT via Supabase...")
auth_url = f"{supabase_url}/auth/v1/signup"
req_auth = urllib.request.Request(auth_url, method="POST")
req_auth.add_header("Content-Type", "application/json")
req_auth.add_header("apikey", anon_key)

try:
    resp_auth = urllib.request.urlopen(req_auth, data=b"{}")
    auth_data = json.loads(resp_auth.read().decode())
    jwt = auth_data.get("access_token")
    if jwt:
        print("   Success! Active JWT Token Extracted.\n")
    else:
        print("   Failed.")
        exit(1)
except Exception as e:
    print(f"   Auth Failed: {e}")
    if hasattr(e, 'read'): print(e.read().decode())
    exit(1)

print("2. Executing Edge Function inference with valid JWT Bearer AND apikey header...")
edge_url = f"{supabase_url}/functions/v1/identify"
req_edge = urllib.request.Request(edge_url, method="POST")
req_edge.add_header("Content-Type", "application/json")
req_edge.add_header("Authorization", f"Bearer {jwt}")
req_edge.add_header("apikey", anon_key) # adding apikey

try:
    resp_edge = urllib.request.urlopen(req_edge, data=b"{}")
    print("\n   ✅ SUCCESS! EDGE FUNCTION RESPONSE:")
    print(f"   {resp_edge.read().decode()}")
except Exception as e:
    print(f"\n   ❌ Edge Function Failed: {e}")
    if hasattr(e, 'read'): 
        error_content = e.read().decode()
        print(f"   Details: {error_content}")
