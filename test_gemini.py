import urllib.request
import json
import os

key = "AIzaSyA4cvLnPE4g4hiwxVKc1N5H0djw3_WEXQc"
url = f"https://generativelanguage.googleapis.com/upload/v1beta/files?uploadType=media&key={key}"
req = urllib.request.Request(url, method="POST")
req.add_header("Content-Type", "image/jpeg")
with open("test.jpg", "wb") as f:
    f.write(b"fake data")

with open("test.jpg", "rb") as f:
    try:
        resp = urllib.request.urlopen(req, data=f.read())
        print(resp.read().decode())
    except Exception as e:
        print(e)
        if hasattr(e, 'read'):
            print(e.read().decode())
