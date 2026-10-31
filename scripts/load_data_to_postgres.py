#!/usr/bin/env python3
"""
Populate Local PostgreSQL with Churn Predictions
Works seamlessly with S3 or local dataset without requiring AWS RDS.
"""

import os
import sys
import argparse
import logging
from datetime import datetime, timedelta
import random
import pandas as pd
import psycopg2
from psycopg2.extras import execute_batch

# Add root directory to sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, PROJECT_ROOT)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("load_data_to_postgres")


def load_env():
    """Load .env file if available"""
    env_path = os.path.join(PROJECT_ROOT, ".env")
    if os.path.exists(env_path):
        with open(env_path, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())


def get_db_connection(host, port, user, password, dbname):
    """Establish connection to PostgreSQL"""
    try:
        conn = psycopg2.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            dbname=dbname
        )
        conn.autocommit = True
        return conn
    except Exception as e:
        logger.error(f"Failed to connect to PostgreSQL at {host}:{port}/{dbname}: {e}")
        logger.info("Make sure the local PostgreSQL container is running: make grafana-up")
        sys.exit(1)


def ensure_tables_exist(conn):
    """Ensure tables and views exist by running create_analytics_tables.sql"""
    sql_file = os.path.join(PROJECT_ROOT, "sql", "create_analytics_tables.sql")
    if os.path.exists(sql_file):
        logger.info(f"Checking/initializing schema from {sql_file}...")
        with open(sql_file, "r", encoding="utf-8") as f:
            sql_script = f.read()
        with conn.cursor() as cur:
            cur.execute(sql_script)
        logger.info("Database schema initialized successfully.")


def try_load_from_s3(bucket, aws_key, aws_secret, aws_region):
    """Attempt to load latest inference predictions from S3"""
    try:
        import boto3
        import io

        logger.info(f"Attempting to fetch predictions from S3 bucket '{bucket}'...")
        s3 = boto3.client(
            's3',
            aws_access_key_id=aws_key,
            aws_secret_access_key=aws_secret,
            region_name=aws_region
        )
        # Search for inference_artifacts
        prefix = "artifacts/inference_artifacts/"
        response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
        if 'Contents' in response and len(response['Contents']) > 0:
            csv_files = [obj['Key'] for obj in response['Contents'] if obj['Key'].endswith('predictions.csv')]
            if csv_files:
                csv_files.sort(reverse=True)
                latest_key = csv_files[0]
                logger.info(f"Found latest S3 predictions file: s3://{bucket}/{latest_key}")
                obj = s3.get_object(Bucket=bucket, Key=latest_key)
                df = pd.read_csv(io.BytesIO(obj['Body'].read()))
                return df
    except Exception as e:
        logger.warning(f"Could not load from S3: {e}")
    return None


def load_local_dataset():
    """Load local raw or clean CSV"""
    paths = [
        os.path.join(PROJECT_ROOT, "data", "raw", "ChurnModelling_Clean.csv"),
        os.path.join(PROJECT_ROOT, "data", "raw", "ChurnModelling.csv")
    ]
    for p in paths:
        if os.path.exists(p):
            logger.info(f"Loading local dataset from {p}...")
            return pd.read_csv(p)
    logger.error("No local dataset found in data/raw/")
    return None


def populate_predictions(conn, df, limit=1000):
    """Insert predictions into churn_predictions and high_risk_customers"""
    if len(df) > limit:
        df = df.sample(n=limit, random_state=42).reset_index(drop=True)

    records = []
    high_risk_records = []
    base_time = datetime.now()

    logger.info(f"Preparing {len(df)} records for PostgreSQL insertion...")

    for i, row in df.iterrows():
        customer_id = str(row.get('CustomerId', row.get('customer_id', 15600000 + i)))
        
        # Determine prediction and probability
        if 'prediction' in row:
            pred = int(row['prediction'])
            prob = float(row.get('probability', 0.85 if pred == 1 else 0.15))
        elif 'predicted_label' in row:
            pred = int(row['predicted_label'])
            prob = float(row.get('prediction_probability', 0.85 if pred == 1 else 0.15))
        elif 'Exited' in row:
            pred = int(row['Exited'])
            prob = float(round(random.uniform(0.65, 0.95), 3) if pred == 1 else round(random.uniform(0.05, 0.35), 3))
        else:
            pred = random.choice([0, 1])
            prob = float(round(random.uniform(0.6, 0.9) if pred == 1 else random.uniform(0.1, 0.4), 3))

        risk_score = prob

        # Spread timestamps across last 24 hours
        time_offset = timedelta(
            hours=random.randint(0, 23),
            minutes=random.randint(0, 59),
            seconds=random.randint(0, 59)
        )
        predicted_at = base_time - time_offset

        geography = str(row.get('Geography', row.get('geography', random.choice(['France', 'Germany', 'Spain']))))
        gender = str(row.get('Gender', row.get('gender', random.choice(['Male', 'Female']))))
        age = int(row.get('Age', row.get('age', random.randint(25, 65))))
        tenure = int(row.get('Tenure', row.get('tenure', random.randint(1, 10))))
        balance = float(row.get('Balance', row.get('balance', round(random.uniform(10000, 150000), 2))))
        num_products = int(row.get('NumOfProducts', row.get('num_of_products', random.randint(1, 4))))
        has_card = int(row.get('HasCrCard', row.get('has_cr_card', 1)))
        is_active = int(row.get('IsActiveMember', row.get('is_active_member', 1)))
        salary = float(row.get('EstimatedSalary', row.get('estimated_salary', round(random.uniform(30000, 120000), 2))))
        event_id = f"ev_{customer_id}_{int(predicted_at.timestamp())}_{i}"

        records.append((
            customer_id, pred, prob, risk_score, predicted_at, "1.0",
            geography, gender, age, tenure, balance, num_products, has_card, is_active, salary, event_id
        ))

        if risk_score >= 0.7:
            high_risk_records.append((
                customer_id, risk_score, geography, gender, age, balance, predicted_at
            ))

    insert_query = """
    INSERT INTO churn_predictions (
        customer_id, prediction, probability, risk_score, predicted_at, model_version,
        geography, gender, age, tenure, balance, num_of_products, has_cr_card, is_active_member, estimated_salary, event_id
    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    ON CONFLICT (event_id) DO NOTHING;
    """

    with conn.cursor() as cur:
        execute_batch(cur, insert_query, records, page_size=200)

        if high_risk_records:
            high_risk_query = """
            INSERT INTO high_risk_customers (
                customer_id, risk_score, geography, gender, age, balance, detected_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (customer_id, detected_at) DO NOTHING;
            """
            execute_batch(cur, high_risk_query, high_risk_records, page_size=200)

    logger.info(f"✅ Successfully inserted {len(records)} predictions into local PostgreSQL!")
    if high_risk_records:
        logger.info(f"🚨 Recorded {len(high_risk_records)} high-risk customer alerts.")


def main():
    load_env()

    parser = argparse.ArgumentParser(description="Populate local PostgreSQL for Grafana")
    parser.add_argument("--source", choices=["auto", "s3", "local"], default="auto", help="Data source to load from")
    parser.add_argument("--host", default=os.getenv("LOCAL_PG_HOST", "localhost"), help="PostgreSQL host")
    parser.add_argument("--port", default=int(os.getenv("LOCAL_PG_PORT", 5432)), help="PostgreSQL port")
    parser.add_argument("--user", default="postgres", help="PostgreSQL user")
    parser.add_argument("--password", default="postgrespostgres", help="PostgreSQL password")
    parser.add_argument("--db", default="churn_analytics", help="PostgreSQL database")
    parser.add_argument("--count", type=int, default=1500, help="Number of records to populate")
    args = parser.parse_args()

    conn = get_db_connection(args.host, args.port, args.user, args.password, args.db)
    ensure_tables_exist(conn)

    df = None
    if args.source in ("auto", "s3"):
        s3_bucket = os.getenv("S3_BUCKET")
        aws_key = os.getenv("AWS_ACCESS_KEY_ID")
        aws_secret = os.getenv("AWS_SECRET_ACCESS_KEY")
        aws_region = os.getenv("AWS_DEFAULT_REGION", "ap-south-1")
        if s3_bucket:
            df = try_load_from_s3(s3_bucket, aws_key, aws_secret, aws_region)

    if df is None:
        logger.info("Using local dataset to populate predictions...")
        df = load_local_dataset()

    if df is None:
        logger.error("Failed to load data from both S3 and local files.")
        sys.exit(1)

    populate_predictions(conn, df, limit=args.count)

    print("\n" + "="*60)
    print("🚀 Data population complete!")
    print("Open Grafana to see your live dashboards:")
    print("👉 http://localhost:3000")
    print("="*60 + "\n")


if __name__ == "__main__":
    main()

