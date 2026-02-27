"""Gauz Platform API — settings loaded from environment."""

import os
from dotenv import load_dotenv

load_dotenv()

# Database
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "mysql+pymysql://root:Aa@123456@localhost:3306/gauz_platform",
)

# JWT
JWT_SECRET = os.getenv("JWT_SECRET", "change-me-in-production")
JWT_ALGORITHM = "HS256"
JWT_EXPIRE_HOURS = int(os.getenv("JWT_EXPIRE_HOURS", "168"))  # 7 days

# Downstream services
CATSCOMPANY_URL = os.getenv("CATSCOMPANY_URL", "http://localhost:6061")
GAUZMEM_URL = os.getenv("GAUZMEM_URL", "http://localhost:1235")

# Container orchestration
XIAOBA_COMPOSE_FILE = os.getenv("XIAOBA_COMPOSE_FILE", "/opt/services/xiaoba/deploy/docker-compose.multitenant.yml")
XIAOBA_REPO_ROOT = os.getenv("XIAOBA_REPO_ROOT", "/opt/services/xiaoba")
TENANTS_DIR = os.getenv("TENANTS_DIR", "/opt/services/xiaoba/tenants")

# LLM proxy (provided to tenants)
LLM_PROXY_PROVIDER = os.getenv("LLM_PROXY_PROVIDER", "anthropic")
LLM_PROXY_API_BASE = os.getenv("LLM_PROXY_API_BASE", "")
LLM_PROXY_API_KEY = os.getenv("LLM_PROXY_API_KEY", "")
LLM_PROXY_MODEL = os.getenv("LLM_PROXY_MODEL", "claude-sonnet-4-20250514")
