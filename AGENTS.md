# AGENTS.md — NaijaReels 协作规则

## 目录
- `backend/` NestJS + Prisma 后端
- `contracts/` OpenAPI 3.1 契约（`openapi.yaml`）与错误码（`errors.md`）
- `infra/` 基础设施配置（nginx 等）
- `.github/workflows/` CI（后端只改 `backend.yml`，前端 `app.yml` 归前端）
- `app/`、`web/` 前端目录，后端任务不得修改

## 分支与合并
- `main` 受保护：只能通过 PR 合并，CI 必须全绿；禁止直接 push、禁止 force push。
- 分支命名：`feat/Tn-xxx`（如 `feat/T3-wallet`），修复可用 `fix/Tn-xxx`。
- Commit 遵循 Conventional Commits（`feat:`、`fix:`、`chore:`、`docs:`、`test:`、`refactor:` …）。
- 修改 `contracts/` 的 PR 标题必须带 `[API]`，并保证 Spectral 无 error。

## API 约定
- 前缀 `/api/v1`；响应 `{code,message,data}`，`code=0` 成功。
- 错误使用真实 HTTP 状态码 + 5 位业务码，见 `contracts/errors.md`；业务异常统一抛 `AppException`。
- 鉴权 Bearer JWT；分页 `page`/`size`，列表返回 `{items,page,size,hasMore}`。
- 金额用 kobo 整数；金币为整数，字段名以 `Coins` 结尾。

## 资金安全
- 金币变动只能通过 `WalletService`，且必须在数据库事务内同时更新钱包并写入 `coin_ledger` 流水（带幂等键）。
- 支付/广告回调（Paystack、Play、AdMob）必须：验签 → 幂等（`payment_events` 唯一键）→ 原始报文落库。
- 禁止存储任何银行卡数据（卡号、CVV、有效期等），支付仅保存渠道引用。
- 禁止提交 `.env` 或任何密钥；新增变量同步写入 `backend/.env.example` 并在 `config/env.ts` 用 zod 校验。

## 本地开发
```bash
docker compose up -d --build     # pg, redis, backend:3000, mock:4010, nginx:8080 (/media)
cd backend && npm ci && npx prisma generate && npm run lint && npm test && npm run build
```
