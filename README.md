# SeeSeaIntelligenceAPI

SeeSea 後端 API 服務 - 全球航運情報分析系統

## 架構概覽

- **api-go**: Go 高性能 API（Gin框架）- 處理70%流量的快速資料查詢和 WebSocket
- **api-python**: Python 分析 API（FastAPI）- 處理30%流量的複雜分析和 LangGraph Agent
- **etl**: ETL Pipeline - 資料處理和同步
- **infrastructure**: 基礎設施配置（Docker, Nginx, 資料庫, 監控）

## 技術棧

### 後端框架
- Go 1.21 + Gin
- Python 3.12 + FastAPI
- LangGraph (AI Agent)

### 資料庫
- PostgreSQL 16 + TimescaleDB (OLTP - 即時寫入)
- ClickHouse 24 (OLAP - 歷史分析)
- Redis 7 (快取層)

### 監控
- Prometheus (指標收集)
- Grafana (視覺化)

## 快速開始

### 1. 環境準備

確保已安裝：
- Docker
- Docker Compose

### 2. 設定環境變數

```bash
# 複製環境變數範例
cp .env.example .env

# 編輯 .env 並填入必要的密碼和 API Keys
nano .env
```

必須設定的環境變數：
```env
POSTGRES_PASSWORD=你的PostgreSQL密碼
CLICKHOUSE_PASSWORD=你的ClickHouse密碼
REDIS_PASSWORD=你的Redis密碼
GRAFANA_PASSWORD=你的Grafana密碼
GEMINI_API_KEY=你的Gemini API Key（用於AI功能）
```

### 3. 啟動所有服務

```bash
# 進入 docker 配置目錄
cd infrastructure/docker

# 啟動所有服務（首次啟動會自動建置映像）
docker-compose up -d

# 查看服務狀態
docker-compose ps

# 查看日誌
docker-compose logs -f
```

### 4. 驗證服務

啟動後，以下服務將可用：

| 服務 | 端口 | 健康檢查 |
|-----|------|---------|
| **Go API** | 8080 | http://localhost:8080/health |
| **Python API** | 8000 | http://localhost:8000/health |
| **PostgreSQL** | 5432 | - |
| **ClickHouse** | 8123, 9000 | http://localhost:8123/ping |
| **Redis** | 6379 | - |
| **Prometheus** | 9090 | http://localhost:9090 |
| **Grafana** | 3001 | http://localhost:3001 |
| **Nginx** | 80, 443 | - |

```bash
# 測試 Go API
curl http://localhost:8080/health

# 測試 Python API
curl http://localhost:8000/health

# 測試 ClickHouse
curl http://localhost:8123/ping
```

### 5. 停止服務

```bash
cd infrastructure/docker

# 停止所有服務
docker-compose down

# 停止並刪除資料卷（警告：會刪除所有資料）
docker-compose down -v
```

## 開發模式

### 單獨運行 Go API

```bash
cd api-go

# 設定環境變數
export DATABASE_URL=postgresql://admin:password@localhost:5432/seesea
export CLICKHOUSE_URL=http://localhost:8123
export REDIS_URL=redis://localhost:6379

# 運行
go run cmd/server/main.go
```

### 單獨運行 Python API

```bash
cd api-python

# 建立虛擬環境
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 安裝依賴
pip install -r requirements.txt

# 設定環境變數
export DATABASE_URL=postgresql://admin:password@localhost:5432/seesea
export CLICKHOUSE_URL=http://localhost:8123
export REDIS_URL=redis://localhost:6379
export GEMINI_API_KEY=your_key

# 運行
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## 🌐 服務端點列表

### 核心 API 服務

| 服務 | 端口 | 訪問地址 | 說明 |
|-----|------|---------|------|
| **Go API** | 8080 | http://localhost:8080 | 高性能資料查詢 API |
| **Python API** | 8000 | http://localhost:8000 | 分析和 AI Agent API |
| **Nginx (反向代理)** | 80 | http://localhost | 統一入口 |

### 資料庫服務

| 服務 | 端口 | 訪問地址 | 說明 |
|-----|------|---------|------|
| **PostgreSQL** | 5432 | localhost:5432 | 即時資料庫 (OLTP) |
| **ClickHouse HTTP** | 8123 | http://localhost:8123 | 分析資料庫 HTTP 接口 |
| **ClickHouse Native** | 9000 | localhost:9000 | 分析資料庫原生接口 |
| **Redis** | 6379 | localhost:6379 | 快取層 |

### 監控服務

| 服務 | 端口 | 訪問地址 | 說明 |
|-----|------|---------|------|
| **Prometheus** | 9090 | http://localhost:9090 | 指標收集 |
| **Grafana** | 3002 | http://localhost:3002 | 監控儀表板 |

## 📋 API 端點詳細說明

### 1. Go API (Port 8080)

#### 健康檢查
```bash
GET http://localhost:8080/health
```

#### 船隻資料查詢
```bash
GET http://localhost:8080/api/v1/vessels/{chokepoint}
參數:
  - chokepoint: 航道名稱 (suez-canal, strait-of-hormuz, etc.)
  - start_date: 開始日期 (YYYY-MM-DD)
  - end_date: 結束日期 (YYYY-MM-DD)

範例:
curl "http://localhost:8080/api/v1/vessels/suez-canal?start_date=2024-01-01&end_date=2024-01-31"
```

#### WebSocket 即時推送
```bash
WS ws://localhost:8080/ws
```

### 2. Python API (Port 8000)

#### 📚 互動式文檔
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
- **OpenAPI Schema**: http://localhost:8000/openapi.json

#### 健康檢查
```bash
GET http://localhost:8000/health
```

#### 分析 API
```bash
# 趨勢分析
GET http://localhost:8000/api/v1/analytics/trend
參數:
  - chokepoint: 航道名稱
  - years: 分析年數 (預設: 5)

# 航道對比分析
POST http://localhost:8000/api/v1/analytics/compare
Body:
{
  "chokepoints": ["suez-canal", "panama-canal"],
  "metric": "vessel_count"
}
```

#### LangGraph AI Agent
```bash
POST http://localhost:8000/api/v1/chat
Body:
{
  "message": "分析蘇伊士運河最近一個月的船隻流量趨勢",
  "session_id": "optional-session-id"
}
```

### 3. Nginx 統一入口 (Port 80)

所有 API 都可以通過 Nginx 訪問：

```bash
# Go API (資料查詢)
http://localhost/api/v1/vessels/*

# Python API (分析)
http://localhost/api/v1/analytics/*

# AI Agent
http://localhost/api/v1/chat

# WebSocket
ws://localhost/ws

# 健康檢查
http://localhost/health
```

### 4. 資料庫連接

#### PostgreSQL
```bash
# 使用 psql 連接
docker compose exec postgres psql -U admin -d seesea

# 或從主機連接
psql -h localhost -p 5432 -U admin -d seesea
密碼: seesea_dev_123
```

#### ClickHouse
```bash
# HTTP 接口
curl http://localhost:8123/ping

# 執行查詢
curl "http://localhost:8123/" --data "SELECT count() FROM vessel_arrivals_analytics"

# 使用 clickhouse-client
docker compose exec clickhouse clickhouse-client
```

#### Redis
```bash
# 使用 redis-cli
docker compose exec redis redis-cli

# 從主機連接
redis-cli -h localhost -p 6379
```

### 5. 監控服務

#### Prometheus
```bash
訪問: http://localhost:9090

常用查詢:
- API 請求率: rate(http_requests_total[5m])
- 資料庫連接數: database_connections
- 記憶體使用: process_resident_memory_bytes
```

#### Grafana
```bash
訪問: http://localhost:3002
用戶名: admin
密碼: admin123 (在 .env 中設定)
```

## 🧪 測試範例

### 測試 Go API
```bash
# 健康檢查
curl http://localhost:8080/health

# 查詢船隻資料
curl "http://localhost:8080/api/v1/vessels/suez-canal?start_date=2024-01-01&end_date=2024-01-31"
```

### 測試 Python API
```bash
# 查看 API 文檔
open http://localhost:8000/docs

# 健康檢查
curl http://localhost:8000/health

# 趨勢分析
curl "http://localhost:8000/api/v1/analytics/trend?chokepoint=suez-canal&years=1"

# AI 對話
curl -X POST http://localhost:8000/api/v1/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "分析最近的航運趨勢"}'
```

### 測試 WebSocket
```bash
# 安裝 wscat
npm install -g wscat

# 連接 WebSocket
wscat -c ws://localhost:8080/ws
```

## 資料流程

```
1. 資料收集 → CSV 檔案
2. ETL Pipeline → PostgreSQL (即時資料)
3. 每日同步 → ClickHouse (歷史分析)
4. API 查詢 → Redis 快取 → 資料庫
```

## 監控與日誌

### 查看日誌

```bash
# 所有服務
docker-compose logs -f

# 特定服務
docker-compose logs -f api-go
docker-compose logs -f api-python
docker-compose logs -f postgres
```

### Grafana 監控

訪問 http://localhost:3001
- 用戶名: `admin`
- 密碼: `.env` 中的 `GRAFANA_PASSWORD`

### Prometheus 指標

訪問 http://localhost:9090

## 常見問題

### 1. 服務無法啟動

```bash
# 查看詳細日誌
docker-compose logs [service-name]

# 重新建置映像
docker-compose build --no-cache

# 清理並重啟
docker-compose down -v
docker-compose up -d
```

### 2. 資料庫連接失敗

確保 `.env` 中的密碼正確，並且資料庫服務已啟動：
```bash
docker-compose ps postgres
docker-compose ps clickhouse
```

### 3. 端口衝突

如果端口已被佔用，可以修改 `docker-compose.yml` 中的端口映射：
```yaml
ports:
  - "8081:8080"  # 改為其他端口
```

## 目錄結構

```
SeeSeaIntelligenceAPI/
├── api-go/              # Go API 服務
│   ├── cmd/            # 程式入口
│   ├── internal/       # 內部程式碼
│   └── pkg/            # 公共套件
├── api-python/         # Python API 服務
│   ├── app/            # FastAPI 應用
│   └── tests/          # 測試
├── etl/                # ETL Pipeline
│   └── jobs/           # ETL 任務
├── infrastructure/     # 基礎設施
│   ├── docker/         # Docker Compose
│   ├── nginx/          # Nginx 配置
│   ├── database/       # 資料庫初始化腳本
│   └── monitoring/     # 監控配置
└── .env               # 環境變數（不要提交到 Git）
```

## 🚀 AWS 部署

### 部署到 EC2

```bash
# 1. 先配置環境變數
cp infrastructure/docker/.env.example infrastructure/docker/.env
# 編輯 .env 填入密碼和 API keys

# 2. 執行部署腳本
./scripts/deploy-aws.sh

# 3. 查看日誌
ssh -i /home/jaqq-fast-doge/kacha.pem ubuntu@ec2-13-52-37-94.us-west-1.compute.amazonaws.com \
  'cd /home/ubuntu/seesea-api/infrastructure/docker && docker-compose logs -f'
```

### 回滾 (Rollback)

如果部署後發現問題，可以快速回滾到上一個版本：

```bash
# 1. 查看可用的備份
./scripts/rollback-aws.sh

# 2. 選擇要回滾的備份版本
./scripts/rollback-aws.sh backup-20260207-143022
```

**rollback 功能說明：**
- 每次部署前會自動備份當前版本
- 保留最近 5 個備份
- 回滾會停止服務 → 恢復舊版本 → 重啟服務
- 回滾前會再創建一個備份點，以防需要回到回滾前的狀態

**使用場景：**
- 新版本有 bug 需要緊急回到上一版
- 部署後發現性能問題
- 配置錯誤導致服務異常

## License

Proprietary
