# SeeSea ETL Pipeline

自動化資料同步與 ETL 管道

## 📊 架構概覽

```
SeeSeaIntelligence (CSV)
         ↓
    [增量 ETL]
         ↓
   PostgreSQL (OLTP)
         ↓
    [每日同步]
         ↓
   ClickHouse (OLAP)
```

## 🔄 ETL 任務

### 1. 增量 CSV → PostgreSQL
- **排程**: 每小時執行 (每小時 00 分)
- **腳本**: `jobs/incremental_csv_to_postgres.py`
- **功能**:
  - 檢查每個航道的最後同步時間 (`collected_at`)
  - 只處理新增或更新的記錄
  - 避免重複處理相同資料
- **效能**:
  - 使用批次插入 (`execute_batch`)
  - 100 條記錄一批
  - `ON CONFLICT DO UPDATE` 自動處理重複

### 2. PostgreSQL → ClickHouse
- **排程**: 每天凌晨 2:00 執行
- **腳本**: `jobs/pg_to_clickhouse.py`
- **功能**:
  - 同步昨天的資料到 ClickHouse
  - 用於歷史分析和複雜查詢
  - 保持 OLTP 和 OLAP 資料同步

## 🚀 快速開始

### 手動執行 ETL

#### 全量同步（首次導入）
```bash
cd /home/jaqq-fast-doge/playground/SeeSea/SeeSeaIntelligenceAPI
/home/jaqq-fast-doge/playground/SeeSea/.venv/bin/python etl/jobs/csv_to_postgres.py
```

#### 增量同步（日常使用）
```bash
cd /home/jaqq-fast-doge/playground/SeeSea/SeeSeaIntelligenceAPI
/home/jaqq-fast-doge/playground/SeeSea/.venv/bin/python etl/jobs/incremental_csv_to_postgres.py
```

#### PostgreSQL → ClickHouse 同步
```bash
cd /home/jaqq-fast-doge/playground/SeeSea/SeeSeaIntelligenceAPI
/home/jaqq-fast-doge/playground/SeeSea/.venv/bin/python etl/jobs/pg_to_clickhouse.py
```

### 自動排程（Docker 容器）

ETL Scheduler 會在 Docker 容器中自動運行：

```bash
# 查看 ETL 容器狀態
docker ps | grep seesea-etl

# 查看 ETL 日誌
docker logs seesea-etl -f

# 重啟 ETL 服務
cd infrastructure/docker
docker compose restart etl
```

## 📁 目錄結構

```
etl/
├── scheduler.py                          # 排程器主程式
├── jobs/
│   ├── csv_to_postgres.py               # 全量 CSV 導入
│   ├── incremental_csv_to_postgres.py   # 增量 CSV 同步 ⭐
│   └── pg_to_clickhouse.py              # PG → ClickHouse 同步
├── requirements.txt                      # Python 依賴
├── Dockerfile                            # Docker 配置
└── README.md                             # 本文檔
```

## 🔧 配置

### 環境變數

在 `SeeSeaIntelligenceAPI/.env` 中設定：

```env
# Database URLs
DATABASE_URL=postgresql://admin:password@localhost:5432/seesea
CLICKHOUSE_URL=http://localhost:8123
REDIS_URL=redis://localhost:6379
```

### 排程時間調整

編輯 `scheduler.py` 修改排程：

```python
# CSV → PostgreSQL: 改為每 30 分鐘
scheduler.add_job(
    csv_to_postgres,
    trigger=CronTrigger(minute='0,30'),  # 0 分和 30 分執行
    id='csv_to_postgres',
    name='CSV to PostgreSQL sync'
)

# PostgreSQL → ClickHouse: 改為每 6 小時
scheduler.add_job(
    pg_to_clickhouse,
    trigger=CronTrigger(hour='*/6'),  # 每 6 小時執行
    id='pg_to_clickhouse',
    name='PostgreSQL to ClickHouse sync'
)
```

## 📊 監控與驗證

### 檢查同步狀態

```bash
# 查看 PostgreSQL 資料
docker exec seesea-postgres psql -U admin -d seesea -c "
SELECT chokepoint, COUNT(*), MAX(date), MAX(updated_at)
FROM vessel_arrivals
GROUP BY chokepoint;
"

# 查看最近更新的記錄
docker exec seesea-postgres psql -U admin -d seesea -c "
SELECT chokepoint, date, vessel_count, updated_at
FROM vessel_arrivals
ORDER BY updated_at DESC
LIMIT 10;
"
```

### 檢查 ETL 日誌

```bash
# 實時查看日誌
docker logs seesea-etl -f --tail 100

# 查看錯誤日誌
docker logs seesea-etl 2>&1 | grep -i error
```

## 🐛 常見問題

### 1. 增量 ETL 沒有檢測到新資料

增量 ETL 基於 `collected_at` 時間戳。如果 CSV 中的 `collected_at` 沒有更新，則不會同步。

**解決方案**：
- 確認 SeeSeaIntelligence 生成 CSV 時更新了 `collected_at`
- 或手動執行全量同步：`python etl/jobs/csv_to_postgres.py`

### 2. 資料庫連接失敗

**錯誤**: `connection to server at "localhost" failed`

**解決方案**：
- 確認 PostgreSQL 容器正在運行：`docker ps | grep postgres`
- 檢查 `.env` 中的密碼是否正確
- 確認端口 5432 沒有被佔用

### 3. ETL 容器一直重啟

```bash
# 查看詳細錯誤
docker logs seesea-etl

# 常見原因：
# 1. CSV 路徑不存在（需要掛載 SeeSeaIntelligence 目錄）
# 2. 資料庫連接失敗
# 3. Python 依賴缺失
```

## 🔄 工作流程

### 正常運行流程

1. **SeeSeaIntelligence** 每天抓取最新航運資料，生成 CSV
2. **增量 ETL** (每小時) 檢查 CSV，只同步新資料到 PostgreSQL
3. **PostgreSQL** 儲存最新資料，TimescaleDB 優化時序查詢
4. **ClickHouse 同步** (每日) 將歷史資料移到 ClickHouse 做分析
5. **API** 從 PostgreSQL 讀取即時資料，從 ClickHouse 做歷史分析

### 首次設定流程

```bash
# 1. 確保資料庫運行
cd infrastructure/docker
docker compose up -d postgres clickhouse

# 2. 執行全量導入
cd ../..
/path/to/venv/bin/python etl/jobs/csv_to_postgres.py

# 3. 啟動 ETL scheduler
docker compose up -d etl

# 4. 驗證資料
docker exec seesea-postgres psql -U admin -d seesea -c "SELECT COUNT(*) FROM vessel_arrivals;"
```

## 📈 效能指標

- **全量導入**: ~15,500 筆記錄，約 5-10 秒
- **增量同步**: 通常 <1 秒 (只處理新資料)
- **批次大小**: 100 條記錄/批次
- **PostgreSQL 索引**: 已優化 `(chokepoint, date)` 查詢

## 🚀 未來改進

- [ ] 新增 ETL 監控儀表板 (Grafana)
- [ ] 實作錯誤重試機制
- [ ] 新增資料品質檢查
- [ ] 支援多種資料來源 (API, S3, etc.)
- [ ] 實作 CDC (Change Data Capture)
