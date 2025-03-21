-- RFM (Recency, Frequency, Monetary) is the core metric for user segmentation in this project.
  -- Recency: Measures how recently a user logged into the website.
  -- Frequency: Evaluates how often a user interacts with the website.
  -- Monetary: Reflects the revenue generated by the user.
-- Fraudulent traffic is excluded to ensure data integrity. Based on the RFM scores, users are segmented into three value groups: high, mid, and low.

{{ config(materialized='view') }}

-- RFM analysis
WITH max_date_in_dataset AS(
  SELECT
    MAX(EXTRACT(DATE FROM accessed_date)) AS max_date
    FROM {{source('source_bq', 'web_logs')}}
),
rfm_analysis AS(
  SELECT 
  wl.ip,
  DATE_DIFF(max_date, MAX(EXTRACT(DATE FROM wl.accessed_date)), DAY) AS last_login_days_ago,
  COUNT (*) AS logins_per_week,
  ROUND (SUM (wl.sales)) AS spent_per_week
  FROM {{source('source_bq', 'web_logs')}} wl
  LEFT JOIN {{ ref('fraud_detected') }} fd ON wl.ip = fd.ip
  JOIN max_date_in_dataset ON TRUE
  WHERE fd.ip IS NULL
  GROUP BY wl.ip, max_date
  ORDER BY spent_per_week DESC, logins_per_week DESC
),
-- user segmentation
percentile AS (
  SELECT
    APPROX_QUANTILES(spent_per_week,100)[OFFSET(63)] AS p63,
    APPROX_QUANTILES(spent_per_week,100)[OFFSET(57)] AS p57
  FROM rfm_analysis
)
SELECT
  rfm.*,
  CASE
    WHEN
      (rfm.logins_per_week > 1)
      AND (rfm.spent_per_week > p.p63)  
    THEN 'high'
    WHEN
      (rfm.logins_per_week = 1)
      AND (rfm.spent_per_week < p.p57)  
    THEN 'low'
    ELSE 'mid'
  END AS user_value
FROM rfm_analysis rfm
JOIN percentile p ON TRUE
ORDER BY 2, rfm.spent_per_week DESC

