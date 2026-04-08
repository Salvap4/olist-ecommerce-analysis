-- Purpose: measure revenue concentration by product category using a Pareto-style cumulative analysis
with category_revenue_base as (
	select 
		coalesce(pcnt.product_category_name_english, nullif(p.product_category_name, ''), 'UNKNOWN') as category,
		(oi.price + oi.freight_value)::numeric as revenue
	from orders o
	join order_items oi on o.order_id = oi.order_id 
	join products p on oi.product_id = p.product_id
	left join product_category_name_translation pcnt on p.product_category_name = pcnt.product_category_name
),
category_revenue_aggregated as (
	select
		category,
		round(sum(revenue), 0) as revenue
	from category_revenue_base
	group by category
),
category_revenue_pareto as (
	select
		rank() over (order by revenue desc) as ranking,
		category,
		revenue,
		sum(revenue) over (order by revenue desc, category) as cum_revenue,
		round(100.0 * revenue / sum(revenue) over (), 2) as pct_revenue,
		round(100.0 * sum(revenue) over (order by revenue desc, category) / sum(revenue) over (), 2) as cum_pct_revenue
	from category_revenue_aggregated
)
select * from category_revenue_pareto
order by ranking, category;