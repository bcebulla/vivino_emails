WITH countries AS (
  SELECT user_id, country_code
  FROM users
  WHERE country_code in ('be','fr','de','nl','dk','it','es','gb','hk','us','ie','ch')--Your countries of interest
),

app_purchases AS (
  SELECT
    o.created_at,
    o.user_id,
    o.id as purchase_id,
    i.vintage_id,
    i.item_total_amount*e.conversion_rate as vintage_gmv_usd
  FROM purchase_orders o
  JOIN purchase_order_items i on i.purchase_order_id = o.id
  JOIN countries c on c.user_id = o.user_id
  JOIN xplenty.exchange_rates_monthly_new e on extract(year from e.date) = extract(year from o.created_at)
                                            and extract(month from e.date) = extract(month from o.created_at)
                                            and convert_to_currency = 'USD'
                                            and e.base_currency = o.currency_code
  WHERE status in (1,3,4)
  AND cancellation_type_id = 0
  AND o.client_name in ('android','iphone','iphone-china')
  ),

attribution AS (
  SELECT
    purchase_id,
    a.created_at,
    a.user_id,
    vintage_id,
    vintage_gmv_usd,
    u.id,
    u.created_at,
    u.related_object_id,
    ROW_NUMBER() OVER (
      PARTITION BY a.user_id, vintage_id
      ORDER BY u.created_at DESC
    ) AS nearest_send
    FROM app_purchases a
    JOIN user_notifications u ON u.user_id = a.user_id
                                  AND u.created_at < a.created_at
                                  AND datediff('hours',u.created_at,a.created_at) BETWEEN 0 and 12--Purchase happened within 12 hours
                                  AND u.user_notification_type_id in (7,8)
  ),

messages AS (
    SELECT
      related_object_id,
      split_part(split_part(extras,'{"manual_message":"',2),'","manual_params',1) as the_message,
      ROW_NUMBER() OVER (
        PARTITION BY related_object_id
        ORDER BY extras DESC
    ) AS row_num
    FROM user_notifications
    GROUP BY
      related_object_id,
      extras
  )

    SELECT
      date(u.created_at) as senddate,
      country_code,
      u.related_object_id,
      the_message,
      count(*) as sends,
      count(distinct a1.purchase_id) as total_orders,
      sum(a1.vintage_gmv_usd) as total_gmv_usd,
      count(distinct a2.purchase_id) as vintage_orders,
      sum(a2.vintage_gmv_usd) as vintage_gmv_usd
    FROM user_notifications u
    JOIN countries on countries.user_id = u.user_id
    LEFT JOIN messages on messages.related_object_id = u.related_object_id
                            and messages.row_num = 1
    LEFT JOIN attribution a1 on a1.id = u.id
                            and a1.nearest_send = 1
    LEFT JOIN attribution a2 on a2.id = u.id
                            and a2.vintage_id = u.related_object_id
                            and a2.nearest_send = 1
    WHERE u.user_notification_type_id in (7,8)
      AND date(u.created_at) >= '2018-12-01'--Dates of interest
    GROUP BY
      date(u.created_at),
      country_code,
      u.related_object_id,
      the_message
    HAVING count(*) >= 100;