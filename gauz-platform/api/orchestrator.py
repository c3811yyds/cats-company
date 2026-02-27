"""Container orchestration — manages XiaoBa tenant containers."""

import json
import os
import shutil
import subprocess
from pathlib import Path

from config import XIAOBA_COMPOSE_FILE, XIAOBA_REPO_ROOT, TENANTS_DIR

TENANT_DIR = Path(TENANTS_DIR)
REPO_ROOT = Path(XIAOBA_REPO_ROOT)
COMPOSE_FILE = Path(XIAOBA_COMPOSE_FILE)

DEFAULT_RUNTIME = {"cpus": "0.4", "mem_limit": "1g", "pids_limit": "512"}
DATA_FOLDERS = ("files", "logs", "workspace", "extracted", "docs_analysis", "docs_runs", "docs_ppt", "audit")


def _run(args: list[str], env: dict | None = None, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=REPO_ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)


def _docker_env(tenant: str) -> dict[str, str]:
    env = os.environ.copy()
    env["TENANT"] = tenant
    for k, v in DEFAULT_RUNTIME.items():
        env[f"TENANT_{k.upper()}"] = v
    return env


def scaffold_tenant(tenant: str, env_content: str) -> None:
    """Create tenant directory structure and write .env."""
    base = TENANT_DIR / tenant
    data = base / "data"
    for folder in DATA_FOLDERS:
        (data / folder).mkdir(parents=True, exist_ok=True)
    (base / ".env").write_text(env_content, encoding="utf-8")
    (base / "runtime.json").write_text(json.dumps(DEFAULT_RUNTIME, indent=2) + "\n", encoding="utf-8")
    # XiaoBa container runs as uid 10001, must own data dirs
    _run(["chown", "-R", "10001:10001", str(data)], timeout=30)


def start_tenant(tenant: str) -> tuple[bool, str]:
    """Start a tenant container. Returns (success, message)."""
    cmd = ["docker", "compose", "-p", f"xiaoba-{tenant}", "-f", str(COMPOSE_FILE), "up", "-d"]
    result = _run(cmd, env=_docker_env(tenant), timeout=900)
    if result.returncode != 0:
        return False, (result.stderr or result.stdout).strip()
    return True, "started"


def stop_tenant(tenant: str) -> tuple[bool, str]:
    cmd = ["docker", "compose", "-p", f"xiaoba-{tenant}", "-f", str(COMPOSE_FILE), "down"]
    result = _run(cmd, env=_docker_env(tenant), timeout=120)
    if result.returncode != 0:
        return False, (result.stderr or result.stdout).strip()
    return True, "stopped"


def tenant_status(tenant: str) -> str:
    result = _run(["docker", "inspect", "-f", "{{.State.Status}}", f"xiaoba-{tenant}"], timeout=30)
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return "not_created"


def remove_tenant(tenant: str) -> None:
    """Stop container and remove tenant directory."""
    stop_tenant(tenant)
    base = TENANT_DIR / tenant
    if base.exists():
        shutil.rmtree(base)
