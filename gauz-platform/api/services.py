"""Downstream service clients — CatsCompany + GauzMem."""

import httpx
from config import CATSCOMPANY_URL, GAUZMEM_URL


async def create_catscompany_user(username: str, password: str, display_name: str) -> dict | None:
    """Register a user in CatsCompany. Returns {token, uid, username} or None."""
    async with httpx.AsyncClient(base_url=CATSCOMPANY_URL, timeout=10) as c:
        resp = await c.post("/api/auth/register", json={
            "username": username,
            "password": password,
            "display_name": display_name,
        })
        if resp.status_code < 400:
            return resp.json()
    return None


async def login_catscompany_user(username: str, password: str) -> dict | None:
    """Login to CatsCompany. Returns {token, uid, username} or None."""
    async with httpx.AsyncClient(base_url=CATSCOMPANY_URL, timeout=10) as c:
        resp = await c.post("/api/auth/login", json={
            "username": username,
            "password": password,
        })
        if resp.status_code < 400:
            return resp.json()
    return None


async def send_friend_request(token: str, target_uid: int) -> bool:
    """Send a friend request in CatsCompany."""
    async with httpx.AsyncClient(base_url=CATSCOMPANY_URL, timeout=10) as c:
        resp = await c.post("/api/friends/request",
            json={"user_id": target_uid},
            headers={"Authorization": f"Bearer {token}"},
        )
        return resp.status_code < 400


async def accept_friend_request(token: str, from_uid: int) -> bool:
    """Accept a friend request in CatsCompany."""
    async with httpx.AsyncClient(base_url=CATSCOMPANY_URL, timeout=10) as c:
        resp = await c.post("/api/friends/accept",
            json={"user_id": from_uid},
            headers={"Authorization": f"Bearer {token}"},
        )
        return resp.status_code < 400


async def create_gauzmem_project(project_id: str) -> bool:
    """Ensure a GauzMem project exists. Returns True on success."""
    try:
        async with httpx.AsyncClient(base_url=GAUZMEM_URL, timeout=5) as c:
            resp = await c.post("/api/v1/projects", json={"project_id": project_id})
            return resp.status_code < 400
    except Exception:
        return False


async def validate_catscompany_token(token: str) -> dict | None:
    """Validate a CatsCompany JWT via /api/me. Returns {uid, username, display_name, account_type} or None."""
    async with httpx.AsyncClient(base_url=CATSCOMPANY_URL, timeout=10) as c:
        resp = await c.get("/api/me", headers={"Authorization": f"Bearer {token}"})
        if resp.status_code == 200:
            return resp.json()
    return None


async def create_catscompany_bot(cc_token: str, username: str, display_name: str, visibility: str = "private") -> dict | None:
    """Create a bot in CatsCompany using the owner's token. Returns {uid, username, api_key, owner_id} or None."""
    async with httpx.AsyncClient(base_url=CATSCOMPANY_URL, timeout=10) as c:
        resp = await c.post("/api/bots", json={
            "username": username,
            "display_name": display_name,
            "visibility": visibility,
        }, headers={"Authorization": f"Bearer {cc_token}"})
        if resp.status_code < 400:
            return resp.json()
    return None


async def accept_friend_request_as_bot(api_key: str, from_uid: int) -> bool:
    """Accept a friend request using bot API key auth."""
    async with httpx.AsyncClient(base_url=CATSCOMPANY_URL, timeout=10) as c:
        resp = await c.post("/api/friends/accept",
            json={"user_id": from_uid},
            headers={"Authorization": f"ApiKey {api_key}"},
        )
        return resp.status_code < 400
