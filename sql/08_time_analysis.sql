-- Purpose: identify the top revenue-generating categories in each month
with monthly_category_revenue_base as (
	select 
		extract(year from o.order_purchase_timestamp::date) as year,
		extract(month from o.order_purchase_timestamp::date) as month,
		oi.price,
		oi.freight_value,
		coalesce(pcnt.product_category_name_english, nullif(p.product_category_name, ''), 'UNKNOWN') as category
	from orders o
	join order_items oi on o.order_id = oi.order_id 
	join products p on oi.product_id = p.product_id
	left join product_category_name_translation pcnt on p.product_category_name = pcnt.product_category_name 
),
monthly_category_revenue as (
	select
		year,
		month,
		category,
		round(sum(price + freight_value)::numeric, 0) as revenue
	from monthly_category_revenue_base
	group by year, month, category
),
monthly_category_revenue_ranked as (
	select
		year,
		month,
		category,
		revenue,
		monthly_category_ranking
	from (
		select
			*,
			rank() over (partition by year, month order by revenue desc) as monthly_category_ranking
		from monthly_category_revenue
	) x
	where monthly_category_ranking <= 3
)
select * from monthly_category_revenue_ranked
order by year, month, monthly_category_ranking;
