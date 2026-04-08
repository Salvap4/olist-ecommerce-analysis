-- Purpose: monthly total revenue trend
with monthly_revenue_base as (
	select
		extract(year from o.order_purchase_timestamp::date) as year,
		extract(month from o.order_purchase_timestamp::date) as month,
		(oi.price + oi.freight_value)::numeric as revenue
	from orders o
	join order_items oi on o.order_id = oi.order_id
)
select
	year,
	month,
	round(sum(revenue), 0) as revenue
from monthly_revenue_base
group by year, month
order by year, month;


-- Purpose: track the monthly revenue evolution of selected key categories identified during the analysis
-- Selected categories:
-- - health_beauty: strong and consistent revenue contributor
-- - bed_bath_table: relevant category with customer experience issues
-- - watches_gifts: category with stronger performance in later periods
with key_category_revenue_base as (
	select
		extract(year from o.order_purchase_timestamp::date) as year,
		extract(month from o.order_purchase_timestamp::date) as month,
		coalesce(pcnt.product_category_name_english, nullif(p.product_category_name, ''), 'UNKNOWN') as category,
		(oi.price + oi.freight_value)::numeric as revenue
	from orders o
	join order_items oi on o.order_id = oi.order_id
	join products p on oi.product_id = p.product_id 
	left join product_category_name_translation pcnt on p.product_category_name = pcnt.product_category_name 
)
select
	year,
	month,
	category,
	round(sum(revenue), 0) as revenue
from key_category_revenue_base
where category in ('bed_bath_table', 'health_beauty', 'watches_gifts')
group by year, month, category
order by year, month, category;
