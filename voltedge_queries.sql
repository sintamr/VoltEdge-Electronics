CREATE TABLE geo_lookup (
    country      VARCHAR(50) PRIMARY KEY,
    region       VARCHAR(50) NOT NULL
);

CREATE TABLE products (
    product_id    INT PRIMARY KEY,
    product_name  VARCHAR(100) NOT NULL,
    category      VARCHAR(50) NOT NULL,
    unit_price    NUMERIC(10,2) NOT NULL
);

CREATE TABLE customers (
    customer_id     INT PRIMARY KEY,
    signup_date     DATE NOT NULL,
    country         VARCHAR(50) NOT NULL REFERENCES geo_lookup(country),
    loyalty_member  BOOLEAN NOT NULL
);

CREATE TABLE orders (
    order_id       INT PRIMARY KEY,
    customer_id    INT NOT NULL REFERENCES customers(customer_id),
    product_id     INT NOT NULL REFERENCES products(product_id),
    order_date     DATE NOT NULL,
    quantity       INT NOT NULL,
    unit_price     NUMERIC(10,2) NOT NULL,
    order_status   VARCHAR(20) NOT NULL,
    country        VARCHAR(50) NOT NULL REFERENCES geo_lookup(country)
);

WITH monthly_sales AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE AS sales_month,
        SUM(quantity * unit_price)             AS revenue,
        COUNT(*)                               AS line_items
    FROM orders
    WHERE order_status = 'Completed'
    GROUP BY 1
)
SELECT
    sales_month,
    revenue,
    line_items,
    ROUND(revenue / NULLIF(line_items, 0), 2) AS avg_value_per_item
FROM monthly_sales
ORDER BY sales_month;

WITH product_revenue AS (
    SELECT
        p.product_name,
        p.category,
        SUM(o.quantity * o.unit_price) AS total_revenue,
        COUNT(*)                       AS total_orders
    FROM orders o
    JOIN products p ON p.product_id = o.product_id
    WHERE o.order_status = 'Completed'
    GROUP BY p.product_name, p.category
)
SELECT
    product_name,
    category,
    total_revenue,
    total_orders,
    RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
FROM product_revenue
ORDER BY revenue_rank;

WITH regional_sales AS (
    SELECT
        g.region,
        SUM(o.quantity * o.unit_price) AS revenue,
        COUNT(*)                       AS total_orders
    FROM orders o
    JOIN geo_lookup g ON g.country = o.country
    WHERE o.order_status = 'Completed'
    GROUP BY g.region
)
SELECT
    region,
    revenue,
    total_orders,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 1) AS pct_of_total_revenue
FROM regional_sales
ORDER BY revenue DESC;

WITH order_with_loyalty AS (
    SELECT
        o.order_id,
        (o.quantity * o.unit_price) AS order_value,
        c.loyalty_member
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'Completed'
)
SELECT
    CASE WHEN loyalty_member THEN 'Loyalty Member' ELSE 'Non-Member' END AS segment,
    COUNT(*)                       AS total_orders,
    SUM(order_value)               AS total_revenue,
    ROUND(AVG(order_value), 2)     AS avg_order_value
FROM order_with_loyalty
GROUP BY loyalty_member
ORDER BY loyalty_member DESC;

WITH product_orders AS (
    SELECT
        p.product_name,
        COUNT(*) FILTER (WHERE o.order_status = 'Returned') AS returned,
        COUNT(*)                                            AS total
    FROM orders o
    JOIN products p ON p.product_id = o.product_id
    GROUP BY p.product_name
)
SELECT
    product_name,
    returned,
    total,
    ROUND(100.0 * returned / total, 1) AS return_rate_pct
FROM product_orders
ORDER BY return_rate_pct DESC;

CREATE OR REPLACE VIEW vw_orders_enriched AS
WITH enriched AS (
    SELECT
        o.order_id,
        o.order_date,
        DATE_TRUNC('month', o.order_date)::DATE AS order_month,
        o.quantity,
        o.unit_price,
        (o.quantity * o.unit_price)  AS line_revenue,
        o.order_status,
        p.product_name,
        p.category,
        g.region,
        o.country,
        c.loyalty_member
    FROM orders o
    JOIN products p    ON p.product_id  = o.product_id
    JOIN customers c   ON c.customer_id = o.customer_id
    JOIN geo_lookup g  ON g.country     = o.country
)
SELECT * FROM enriched;