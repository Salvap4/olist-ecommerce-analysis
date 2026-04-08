-- Note: Olist reviews are linked to orders, not individual products.
-- Category-level experience metrics therefore use order reviews as a proxy.


-- Purpose: measure customer experience at category level by combining revenue, order volume, and average review score
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
category_experience_base as (
	select 
		o.order_id,
		lr.review_score,
		oi.product_id,
		oi.price,
		oi.freight_value,
		coalesce(pcnt.product_category_name_english, nullif(p.product_category_name, ''), 'UNKNOWN') as category
	from orders o
	left join last_review lr on o.order_id = lr.order_id
	join order_items oi on o.order_id = oi.order_id
	join products p on oi.product_id = p.product_id
	left join product_category_name_translation pcnt on p.product_category_name = pcnt.product_category_name 
),
category_metrics as (
	select 
		category,
		round(sum(price + freight_value)::numeric, 0) as revenue,
		round(avg(review_score)::numeric, 2) as avg_review_score,
		count(distinct order_id) as orders_in_category
	from category_experience_base
	group by category
)
select * from category_metrics
order by revenue desc;



-- Purpose: identify high-revenue categories with below-average customer satisfaction
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
category_experience_base as (
	select 
		o.order_id,
		lr.review_score,
		oi.product_id,
		oi.price,
		oi.freight_value,
		coalesce(pcnt.product_category_name_english, nullif(p.product_category_name, ''), 'UNKNOWN') as category
	from orders o
	left join last_review lr on o.order_id = lr.order_id
	join order_items oi on o.order_id = oi.order_id
	join products p on oi.product_id = p.product_id
	left join product_category_name_translation pcnt on p.product_category_name = pcnt.product_category_name 
),
category_experience_metrics as (
	select 
		category,
		round(sum(price + freight_value)::numeric, 0) as revenue,
		round(avg(review_score)::numeric, 2) as avg_review_score,
		count(distinct order_id) as orders_in_category,
		round(100.0 * count(review_score) filter (where review_score <= 2) / nullif(count(review_score), 0), 1) as pct_review_1_2,
		round(100.0 * count(review_score) filter (where review_score = 3) / nullif(count(review_score), 0), 1) as pct_review_3,
		round(100.0 * count(review_score) filter (where review_score = 4) / nullif(count(review_score), 0), 1) as pct_review_4,
		round(100.0 * count(review_score) filter (where review_score = 5) / nullif(count(review_score), 0), 1) as pct_review_5
	from category_experience_base
	group by category
	having count(distinct order_id) >= 100
),
category_experience_benchmarked as (
	select 
		category,
		revenue,
		avg_review_score,
		orders_in_category,
		pct_review_1_2,
		pct_review_3,
		pct_review_4,
		pct_review_5,
		round(avg(revenue) over()::numeric, 0) as global_avg_revenue,
		round(avg(avg_review_score) over()::numeric, 2) as global_avg_review_score
	from category_experience_metrics
),
high_revenue_low_review as (
	select 
		category,
		revenue,
		avg_review_score,
		orders_in_category,
		pct_review_1_2,
		pct_review_3,
		pct_review_4,
		pct_review_5,
		global_avg_revenue,
		global_avg_review_score
	from category_experience_benchmarked
	where revenue > global_avg_revenue and avg_review_score < global_avg_review_score
	-- Use global category averages as a simple benchmark to identify high-revenue, below-average-satisfaction categories
)
select * from high_revenue_low_review
order by revenue desc, avg_review_score asc;
