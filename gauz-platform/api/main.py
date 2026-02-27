"""Gauz Platform API — main application."""

import re
import secrets

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy.orm import Session

from auth import create_token, decode_token
from models import init_db, get_db, User, Agent, InviteCode
from config import (
    LLM_PROXY_PROVIDER, LLM_PROXY_API_BASE, LLM_PROXY_API_KEY, LLM_PROXY_MODEL,
    GAUZMEM_URL, CATSCOMPANY_URL,
)
import orchestrator
import services

app = FastAPI(title="Gauz Platform API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

TENANT_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{1,31}$")


@app.on_event("startup")
def startup():
    init_db()


# ── Auth dependency ──────────────────────────────────

def get_current_user(request: Request, db: Session = Depends(get_db)) -> User:
    auth = request.headers.get("authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(401, "Invalid token")
    payload = decode_token(auth[7:])
    if not payload:
        raise HTTPException(401, "Invalid token")
    user = db.query(User).filter(User.id == int(payload["sub"])).first()
    if not user:
        raise HTTPException(401, "User not found")
    return user


# ── Schemas ──────────────────────────────────────────

class RegisterReq(BaseModel):
    username: str
    password: str
    display_name: str = ""
    invite_code: str = ""

class LoginReq(BaseModel):
    username: str
    password: str

class CreateAgentReq(BaseModel):
    name: str = "小八"

class UpdateSettingsReq(BaseModel):
    feishu_app_id: str = ""
    feishu_app_secret: str = ""


# ── Auth endpoints ───────────────────────────────────

@app.post("/api/auth/register")
async def register(req: RegisterReq, db: Session = Depends(get_db)):
    if len(req.username) < 3 or len(req.password) < 6:
        raise HTTPException(400, "Username >= 3 chars, password >= 6 chars")

    if db.query(User).filter(User.username == req.username).first():
        raise HTTPException(409, "Username taken")

    # Validate invite code
    if req.invite_code:
        invite = db.query(InviteCode).filter(InviteCode.code == req.invite_code).first()
        if not invite or invite.used_count >= invite.max_uses:
            raise HTTPException(400, "Invalid or expired invite code")
        invite.used_count += 1

    # Register in CatsCompany first — it is the auth source of truth
    cc_reg = await services.create_catscompany_user(
        username=req.username,
        password=req.password,
        display_name=req.display_name or req.username,
    )
    if not cc_reg:
        raise HTTPException(502, "CatsCompany registration failed")

    cc_uid = cc_reg.get("uid", 0)

    # Login to CatsCompany to get a token
    cc_login = await services.login_catscompany_user(req.username, req.password)
    cc_token = cc_login.get("token", "") if cc_login else ""

    # Create local user record (no password — CatsCompany owns auth)
    user = User(
        username=req.username,
        display_name=req.display_name or req.username,
        invite_code=req.invite_code,
        catscompany_uid=cc_uid,
        catscompany_token=cc_token,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    return {
        "token": create_token(user.id, user.username),
        "user": {"id": user.id, "username": user.username, "display_name": user.display_name},
    }


@app.post("/api/auth/login")
async def login(req: LoginReq, db: Session = Depends(get_db)):
    # Authenticate via CatsCompany — it is the source of truth
    cc_result = await services.login_catscompany_user(req.username, req.password)
    if not cc_result:
        raise HTTPException(401, "Invalid credentials")

    cc_token = cc_result.get("token", "")
    cc_uid = cc_result.get("uid", 0)
    cc_display = cc_result.get("display_name", req.username)

    # Find or create local user record
    user = db.query(User).filter(User.username == req.username).first()
    if not user:
        user = User(
            username=req.username,
            display_name=cc_display,
            catscompany_uid=cc_uid,
            catscompany_token=cc_token,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    else:
        # Refresh CC token and uid
        user.catscompany_token = cc_token
        if not user.catscompany_uid:
            user.catscompany_uid = cc_uid
        db.commit()

    return {
        "token": create_token(user.id, user.username),
        "user": {"id": user.id, "username": user.username, "display_name": user.display_name},
    }


# ── Agent endpoints ─────────────────────────────────

def _make_tenant_name(user_id: int, agent_name: str) -> str:
    slug = re.sub(r"[^a-z0-9]", "", agent_name.lower())[:8] or "agent"
    suffix = secrets.token_hex(2)
    return f"u{user_id}-{slug}-{suffix}"


def _generate_tenant_env(
    tenant: str, user: User, agent_name: str,
    cc_api_key: str = "",
) -> str:
    project_id = f"user-{user.id}"
    lines = [
        f"# Auto-generated for {user.username} / {agent_name}",
        f"TENANT={tenant}",
        "",
        f"GAUZ_LLM_PROVIDER={LLM_PROXY_PROVIDER}",
        f"GAUZ_LLM_API_BASE={LLM_PROXY_API_BASE}",
        f"GAUZ_LLM_API_KEY={LLM_PROXY_API_KEY}",
        f"GAUZ_LLM_MODEL={LLM_PROXY_MODEL}",
        "",
        "GAUZ_MEM_ENABLED=true",
        f"GAUZ_MEM_BASE_URL={GAUZMEM_URL}",
        f"GAUZ_MEM_PROJECT_ID={project_id}",
        f"GAUZ_MEM_USER_ID={user.username}",
        "",
        f"CATSCOMPANY_SERVER_URL=ws://172.17.0.1:6061/v0/channels",
        f"CATSCOMPANY_API_KEY={cc_api_key}",
        "",
        "GAUZ_TOOL_ALLOW=",
        "",
    ]
    return "\n".join(lines) + "\n"


@app.post("/api/agents")
async def create_agent(
    req: CreateAgentReq,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Limit: 3 agents per user
    count = db.query(Agent).filter(Agent.user_id == user.id).count()
    if count >= 3:
        raise HTTPException(400, "Max 3 agents per user")

    tenant = _make_tenant_name(user.id, req.name)
    project_id = f"agent-{tenant}"

    # Create GauzMem project (best-effort)
    await services.create_gauzmem_project(project_id)

    # Create CatsCompany bot using owner's token (new owner-based API)
    cc_uid = 0
    cc_api_key = ""
    if user.catscompany_token:
        cc_result = await services.create_catscompany_bot(
            cc_token=user.catscompany_token,
            username=f"agent-{tenant}",
            display_name=req.name,
            visibility="private",
        )
        if cc_result:
            cc_uid = cc_result.get("uid", 0)
            cc_api_key = cc_result.get("api_key", "")

    # Auto-add agent as friend to user's CatsCompany account
    if cc_uid and user.catscompany_uid and user.catscompany_token:
        # User sends friend request to agent bot
        await services.send_friend_request(user.catscompany_token, cc_uid)
        # Bot accepts via API key auth
        await services.accept_friend_request_as_bot(cc_api_key, user.catscompany_uid)

    # Scaffold tenant directory + .env
    env_content = _generate_tenant_env(
        tenant, user, req.name,
        cc_api_key=cc_api_key,
    )
    orchestrator.scaffold_tenant(tenant, env_content)

    # Start container
    ok, msg = orchestrator.start_tenant(tenant)

    agent = Agent(
        user_id=user.id,
        name=req.name,
        tenant_name=tenant,
        gauzmem_project_id=project_id,
        catscompany_uid=cc_uid,
        status="running" if ok else "error",
    )
    db.add(agent)
    db.commit()
    db.refresh(agent)

    return {
        "agent": _agent_dict(agent),
        "started": ok,
        "message": msg,
    }


@app.get("/api/agents")
def list_agents(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    agents = db.query(Agent).filter(Agent.user_id == user.id).all()
    result = []
    for a in agents:
        d = _agent_dict(a)
        d["container_status"] = orchestrator.tenant_status(a.tenant_name)
        result.append(d)
    return {"agents": result}


@app.delete("/api/agents/{agent_id}")
def delete_agent(
    agent_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    agent = db.query(Agent).filter(Agent.id == agent_id, Agent.user_id == user.id).first()
    if not agent:
        raise HTTPException(404, "Agent not found")

    orchestrator.remove_tenant(agent.tenant_name)
    db.delete(agent)
    db.commit()
    return {"ok": True}


@app.put("/api/agents/{agent_id}/settings")
def update_agent_settings(
    agent_id: int,
    req: UpdateSettingsReq,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    agent = db.query(Agent).filter(Agent.id == agent_id, Agent.user_id == user.id).first()
    if not agent:
        raise HTTPException(404, "Agent not found")

    # Append feishu config to tenant .env
    from pathlib import Path
    env_path = Path(orchestrator.TENANT_DIR) / agent.tenant_name / ".env"
    if env_path.exists():
        content = env_path.read_text()
        # Remove old feishu lines
        lines = [l for l in content.splitlines() if not l.startswith("FEISHU_")]
        if req.feishu_app_id:
            lines.append(f"FEISHU_APP_ID={req.feishu_app_id}")
            lines.append(f"FEISHU_APP_SECRET={req.feishu_app_secret}")
        env_path.write_text("\n".join(lines) + "\n")

    return {"ok": True}


@app.post("/api/agents/{agent_id}/restart")
def restart_agent(
    agent_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    agent = db.query(Agent).filter(Agent.id == agent_id, Agent.user_id == user.id).first()
    if not agent:
        raise HTTPException(404, "Agent not found")

    orchestrator.stop_tenant(agent.tenant_name)
    ok, msg = orchestrator.start_tenant(agent.tenant_name)
    agent.status = "running" if ok else "error"
    db.commit()
    return {"ok": ok, "message": msg}


# ── Admin endpoints ─────────────────────────────────

@app.post("/api/admin/invite-codes")
def create_invite_code(
    max_uses: int = 10,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    code = secrets.token_urlsafe(8)
    invite = InviteCode(code=code, max_uses=max_uses)
    db.add(invite)
    db.commit()
    return {"code": code, "max_uses": max_uses}


# ── Helpers ─────────────────────────────────────────

def _agent_dict(a: Agent) -> dict:
    return {
        "id": a.id,
        "name": a.name,
        "tenant_name": a.tenant_name,
        "gauzmem_project_id": a.gauzmem_project_id,
        "status": a.status,
        "created_at": a.created_at.isoformat() if a.created_at else None,
    }
