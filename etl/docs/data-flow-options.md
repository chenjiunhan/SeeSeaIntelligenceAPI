# CSV 資料流方案比較

## 問題
SeeSeaIntelligence 產生 CSV 後，ETL 容器如何取得這些檔案？

## 解決方案

### 選項 1: 本地共享目錄 (目前使用)

**架構**:
```
SeeSeaIntelligence/processed/  <--- 產生 CSV
              ↓
    (Docker volume mount)
              ↓
ETL Container /data/processed/  <--- 讀取 CSV
```

**docker-compose.yml 配置**:
```yaml
services:
  etl:
    volumes:
      - ../../../SeeSeaIntelligence/processed:/data/processed:ro
```

**優點**:
- ✅ 設定簡單
- ✅ 本地開發方便
- ✅ 零延遲（直接檔案系統）
- ✅ 不需額外服務

**缺點**:
- ❌ 兩個服務必須在同一台機器
- ❌ 無法分散部署
- ❌ 檔案權限問題

**適用場景**:
- 本地開發環境
- 單機部署
- POC/測試階段

---

### 選項 2: Docker Shared Volume

**架構**:
```
SeeSeaIntelligence Container
         ↓
   [Shared Volume]
         ↓
    ETL Container
```

**docker-compose.yml 配置**:
```yaml
version: '3.9'

volumes:
  csv_data:  # 共享 volume

services:
  # SeeSeaIntelligence 資料收集服務
  data-collector:
    build:
      context: ../../SeeSeaIntelligence
      dockerfile: Dockerfile
    container_name: seesea-collector
    volumes:
      - csv_data:/app/processed
    environment:
      - OUTPUT_DIR=/app/processed
    restart: unless-stopped
    networks:
      - seesea-network

  # ETL 服務
  etl:
    build:
      context: ../../etl
    container_name: seesea-etl
    volumes:
      - csv_data:/data/processed:ro  # 唯讀
    depends_on:
      - data-collector
      - postgres
    networks:
      - seesea-network
```

**優點**:
- ✅ 服務解耦
- ✅ Docker 原生支援
- ✅ 檔案權限管理較好
- ✅ 可以獨立重啟服務

**缺點**:
- ❌ 仍限同一台 Docker host
- ❌ Volume 管理複雜度增加

**適用場景**:
- Docker Compose 部署
- 單機但多容器環境
- 中小型專案

---

### 選項 3: S3/MinIO 雲端儲存 ⭐ 推薦生產環境

**架構**:
```
SeeSeaIntelligence
    ↓ upload
   S3 Bucket (or MinIO)
    ↓ download
  ETL Service
```

**步驟**:

1. **安裝 MinIO (開源 S3)**:
```yaml
# docker-compose.yml
services:
  minio:
    image: minio/minio
    container_name: seesea-minio
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      - MINIO_ROOT_USER=admin
      - MINIO_ROOT_PASSWORD=your_password
    volumes:
      - minio_data:/data
    command: server /data --console-address ":9001"
    networks:
      - seesea-network

volumes:
  minio_data:
```

2. **修改 SeeSeaIntelligence 上傳 CSV**:
```python
# SeeSeaIntelligence/src/uploader.py
import boto3
from pathlib import Path

s3_client = boto3.client(
    's3',
    endpoint_url='http://minio:9000',
    aws_access_key_id='admin',
    aws_secret_access_key='your_password'
)

def upload_csv(local_path: Path):
    """上傳 CSV 到 S3"""
    bucket = 'seesea-data'
    key = f'logistics/chokepoints/{local_path.name}'
    s3_client.upload_file(str(local_path), bucket, key)
```

3. **修改 ETL 讀取 S3**:
```python
# etl/jobs/s3_to_postgres.py
import boto3
import pandas as pd
from io import BytesIO

s3_client = boto3.client(
    's3',
    endpoint_url='http://minio:9000',
    aws_access_key_id='admin',
    aws_secret_access_key='your_password'
)

def load_csv_from_s3():
    """從 S3 下載並處理 CSV"""
    bucket = 'seesea-data'

    # 列出所有 CSV 檔案
    response = s3_client.list_objects_v2(
        Bucket=bucket,
        Prefix='logistics/chokepoints/'
    )

    for obj in response.get('Contents', []):
        if obj['Key'].endswith('.csv'):
            # 下載檔案
            csv_obj = s3_client.get_object(Bucket=bucket, Key=obj['Key'])
            df = pd.read_csv(BytesIO(csv_obj['Body'].read()))

            # 處理資料...
            process_csv(df)
```

**優點**:
- ✅ 服務完全解耦
- ✅ 可分散部署（不同機器/雲）
- ✅ 支援多個 ETL 消費者
- ✅ 檔案版本管理
- ✅ 可加入 CDN/快取
- ✅ 備份與恢復容易

**缺點**:
- ❌ 需要額外 S3 服務
- ❌ 網路延遲
- ❌ 實作複雜度較高

**適用場景**:
- 生產環境
- 分散式部署
- 多服務消費同一資料源
- 需要資料版本控制

---

### 選項 4: 資料庫直接寫入 (跳過 CSV)

**架構**:
```
SeeSeaIntelligence
    ↓ 直接寫入
  PostgreSQL
    ↓ 已經在資料庫
  (不需要 CSV ETL)
```

**修改 SeeSeaIntelligence**:
```python
# 爬蟲完成後直接寫 DB
import psycopg2

def save_vessel_data(data):
    conn = psycopg2.connect(os.getenv('DATABASE_URL'))
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO vessel_arrivals (date, chokepoint, vessel_count, ...)
        VALUES (%s, %s, %s, ...)
        ON CONFLICT (date, chokepoint) DO UPDATE ...
    """, data)

    conn.commit()
```

**優點**:
- ✅ 最簡單（跳過 ETL）
- ✅ 即時資料更新
- ✅ 減少儲存成本
- ✅ 不需要檔案管理

**缺點**:
- ❌ 失去原始資料備份（CSV）
- ❌ 難以追溯資料來源
- ❌ 爬蟲與 DB 耦合
- ❌ 無法重播歷史資料

**適用場景**:
- 簡單應用
- 不需要資料湖
- 即時性要求高

---

## 推薦方案

### 開發環境
**選項 1: 本地共享目錄** (目前使用)
- 最簡單，適合快速開發

### 測試/預生產環境
**選項 2: Docker Shared Volume**
- 更接近生產環境
- 便於測試完整流程

### 生產環境
**選項 3: S3/MinIO**
- 最穩健、可擴展
- 支援分散式架構

---

## 實作建議

### 階段 1: 保持現狀 (開發)
使用本地共享目錄，快速迭代功能

### 階段 2: Docker Volume (測試)
```bash
# 把 SeeSeaIntelligence Docker 化
cd SeeSeaIntelligence
# 創建 Dockerfile

# 修改 docker-compose.yml 加入共享 volume
```

### 階段 3: MinIO (生產)
```bash
# 部署 MinIO
docker compose up -d minio

# 修改上傳/下載邏輯
pip install boto3
```

---

## 當前配置檢查

查看目前的掛載:
```bash
docker inspect seesea-etl --format '{{json .Mounts}}' | python3 -m json.tool
```

測試 ETL 是否能讀取 CSV:
```bash
docker exec seesea-etl ls -la /data/processed/logistics/chokepoints/
```

手動觸發 ETL:
```bash
docker exec seesea-etl python -c "
import sys
sys.path.insert(0, 'jobs')
from incremental_csv_to_postgres import load_incremental_csv_to_postgres
load_incremental_csv_to_postgres()
"
```
