-- Note: Olist reviews are linked to orders, not individual products.
-- Category-level experience metrics therefore use order reviews as a proxy.

-- RFM segmentation logic reused intentionally to keep each analysis file self-contained


-- Purpose: identify potentially problematic products inside the main problematic category among high-value customer segments
with last_review as (
	select
		order_id,
		review_score
	from (
		select
			order_id,
			review_score,
			row_number() over (partition by order_id order by review_creation_date desc, review_id desc) as rn
		from order_reviews
	) x
	where rn = 1
),
order_item_customer_base as (
	select
		o.order_id,
		c.customer_unique_id,
		oi.product_id,
		o.order_purchase_timestamp,
		oi.price,
		oi.freight_value,
		lr.review_score,
		coalesce(pcnt.product_category_name_english, nullif(p.product_category_name, ''), 'UNKNOWN') as category
	from orders o
	join customers c on o.customer_id = c.customer_id
	join order_items oi on o.order_id = oi.order_id
	left join last_review lr on o.order_id = lr.order_id
	join products p on oi.product_id = p.product_id 
	left join product_category_name_translation pcnt on p.product_category_name = pcnt.product_category_name 
),
customer_rfm_base as (
	select
		customer_unique_id,
		max(order_purchase_timestamp)::date as last_order_date,
		date '2018-10-17' - max(order_purchase_timestamp)::date as recency_days,
		count(distinct order_id) as frequency,
		round(sum(price + freight_value)::numeric, 0) as monetary
	from order_item_customer_base
	group by customer_unique_id
),
customer_rfm_scores as (
	select 
		customer_unique_id,
		last_order_date,
		recency_days,
		ntile(5) over(order by recency_days desc) as recency_score,
		frequency,
		case 
			when frequency = 1 then 1
			when frequency = 2 then 2
			when frequency = 3 then 3
			when frequency between 4 and 5 then 4
			else 5
		end as frequency_score,
		monetary,
		ntile(5) over (order by monetary asc) as monetary_score
	from customer_rfm_base
),
customer_segmentation as (
	select
		customer_unique_id,
		case 
			when recency_score >= 4 and monetary_score >= 4 then 'CHAMPION'
			when monetary_score = 5 and frequency_score <= 2 then 'BIG SPENDER'
			when frequency_score >= 3 then 'LOYAL CUSTOMER'
			when recency_score <= 2 and frequency_score >= 2 then 'AT RISK'
			when recency_score >= 4 and frequency_score = 1 then 'POTENTIAL LOYALIST'
			when frequency_score = 1 and monetary_score <= 2 then 'LOW VALUE / ONE TIME BUYER'
			else 'REGULAR CUSTOMER'
		end as customer_segment		
	from customer_rfm_scores 
),
problem_category_high_value_base as (
	select
		cs.customer_segment,
		oicb.category,
		oicb.order_id,
		oicb.product_id,
		oicb.price,
		oicb.freight_value,
		oicb.review_score
	from order_item_customer_base oicb
	join customer_segmentation cs on oicb.customer_unique_id = cs.customer_unique_id 
	where
		cs.customer_segment in ('CHAMPION', 'BIG SPENDER') and
		oicb.category = 'bed_bath_table'
),
problem_category_product_metrics as (
	select
		product_id,
		count(order_id) as orders_count,
		round(sum(price + freight_value)::numeric, 0) as revenue,
		round(avg(review_score)::numeric, 2) as avg_review_score
	from problem_category_high_value_base 
	group by product_id
	having count(distinct order_id) >= 10	-- Keep only products with a minimum number of orders to avoid unstable review averages and low-volume noise
)
select * from problem_category_product_metrics
order by avg_review_score asc, revenue desc;