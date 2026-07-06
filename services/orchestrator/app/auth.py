from fastapi import HTTPException
import os
from typing import Dict, Any

# existing imports
from .vault import get_secret

KEYCLOAK_URL = os.environ.get('KEYCLOAK_URL', 'http://keycloak:8081')
REALM = os.environ.get('KEYCLOAK_REALM', 'master-agent-realm')
CLIENT_ID = os.environ.get('KEYCLOAK_CLIENT_ID', 'master-agent-client')
CLIENT_SECRET = os.environ.get('KEYCLOAK_CLIENT_SECRET', None)

INTROSPECT_URL = f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/token/introspect"


def _ensure_client_secret():
    global CLIENT_SECRET
    if CLIENT_SECRET:
        return
    # attempt to read from Vault
    try:
        secret = get_secret('keycloak', 'client_secret')
        if secret:
            CLIENT_SECRET = secret
            return
    except Exception:
        pass


def introspect_token(token: str) -> Dict[str, Any]:
    _ensure_client_secret()
    if not CLIENT_ID or not CLIENT_SECRET:
        raise HTTPException(status_code=500, detail='Keycloak client credentials not configured')

    import requests
    data = {
        'token': token,
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET
    }
    try:
        resp = requests.post(INTROSPECT_URL, data=data, timeout=5)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f'Failed to reach Keycloak introspect endpoint: {e}')

    if resp.status_code != 200:
        raise HTTPException(status_code=503, detail='Keycloak introspection returned non-200 status')

    info = resp.json()
    return info


def get_roles_from_introspect(info: Dict[str, Any]):
    roles = []
    try:
        realm_access = info.get('realm_access') or {}
        roles = realm_access.get('roles', [])
    except Exception:
        roles = []
    try:
        resource_access = info.get('resource_access') or {}
        client_roles = resource_access.get(CLIENT_ID, {}).get('roles', [])
        roles = list(set(roles + client_roles))
    except Exception:
        pass
    return roles


def verify_token_and_get_user(authorization_header: str):
    if not authorization_header:
        raise HTTPException(status_code=401, detail='Missing Authorization header')
    parts = authorization_header.split()
    if parts[0].lower() != 'bearer' or len(parts) != 2:
        raise HTTPException(status_code=401, detail='Invalid Authorization header')
    token = parts[1]
    info = introspect_token(token)
    if not info.get('active'):
        raise HTTPException(status_code=401, detail='Token is not active')
    user = {
        'username': info.get('preferred_username') or info.get('username'),
        'sub': info.get('sub'),
        'email': info.get('email'),
        'roles': get_roles_from_introspect(info),
        'raw': info
    }
    return user


def has_role(user: Dict[str, Any], required: str) -> bool:
    return required in (user.get('roles') or [])
