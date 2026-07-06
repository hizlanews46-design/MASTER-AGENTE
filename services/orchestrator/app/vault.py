import os
import requests
from fastapi import HTTPException
from typing import Optional

VAULT_ADDR = os.environ.get('VAULT_ADDR', 'http://vault:8200')
VAULT_TOKEN = os.environ.get('VAULT_TOKEN') or os.environ.get('VAULT_ROOT_TOKEN')

def read_kv_v2(path: str) -> Optional[dict]:
    """Read a KV v2 secret from Vault at secret/data/{path}.
    Returns the data dict or None on failure.
    """
    if not VAULT_TOKEN:
        return None
    url = f"{VAULT_ADDR}/v1/secret/data/{path}"
    headers = {'X-Vault-Token': VAULT_TOKEN}
    try:
        resp = requests.get(url, headers=headers, timeout=5)
        if resp.status_code != 200:
            return None
        body = resp.json()
        return body.get('data', {}).get('data')
    except Exception:
        return None

def get_secret(path: str, key: str) -> Optional[str]:
    data = read_kv_v2(path)
    if not data:
        return None
    return data.get(key)
