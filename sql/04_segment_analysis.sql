-- RFM segmentation logic reused intentionally to keep each analysis file self-contained


-- Purpose: compare the category mix of revenue within Champion and Big Spender customer segments
with order_item_customer_base as (
	select 
		o.order_id,
		o.order_purchase_timestamp,
		c.customer_unique_id,
		p.product_id,
		oi.price,
		oi.freight_value,
		coalesce(pcnt.product_category_name_english, nullif(p.product_category_name, ''), 'UNKNOWN') as category
	from orders o
	join order_items oi on o.order_id = oi.order_id 
	join products p on oi.product_id = p.product_id
	join customers c on o.customer_id = c.customer_id
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
		ntile(5) over (order by recency_days desc) as recency_score,
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
segment_enriched_order_items as (
	select 
		oicb.order_id,
		oicb.order_purchase_timestamp,
		oicb.customer_unique_id,
		oicb.product_id,
		oicb.price,
		oicb.freight_value,
		oicb.category,
		cs.customer_segment
	from order_item_customer_base oicb
	join customer_segmentation cs on oicb.customer_unique_id = cs.customer_unique_id
	where cs.customer_segment in ('CHAMPION', 'BIG SPENDER')
),
segment_category_aggregated as (
	select
		customer_segment,
		category,
		round(sum(price + freight_value)::numeric, 0) as revenue,
		count(distinct order_id) as orders_count
	from segment_enriched_order_items
	group by customer_segment, category
),
segment_category_metrics as (
	select	
		customer_segment,
		category,
		revenue,
		orders_count,
		rank() over (partition by customer_segment order by revenue desc) as ranking,
		round((100.0 * revenue / sum(revenue) over(partition by customer_segment)), 2) as pct_revenue_in_customersegment
	from segment_category_aggregated
)
select * from segment_category_metrics
where ranking <= 15;



-- Purpose: identify which categories are relatively more important for Champions versus Big Spenders
with order_item_customer_base as (
	select 
		o.order_id,
		o.order_purchase_timestamp,
		c.customer_unique_id,
		oi.price,
		oi.freight_value,
		coalesce(pcnt.product_category_name_english, nullif(p.product_category_name, ''), 'UNKNOWN') as category
	from orders o
	join order_items oi on o.order_id = oi.order_id 
	join products p on oi.product_id = p.product_id
	join customers c on o.customer_id = c.customer_id
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
		ntile(5) over (order by recency_days desc) as recency_score,
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
segment_enriched_order_items as (
	select 
		oicb.order_id,
		oicb.customer_unique_id,
		oicb.price,
		oicb.freight_value,
		oicb.category,
		cs.customer_segment
	from order_item_customer_base oicb
	join customer_segmentation cs on oicb.customer_unique_id = cs.customer_unique_id
	where cs.customer_segment in ('CHAMPION', 'BIG SPENDER')
),
segment_category_aggregated as (
	select
		customer_segment,
		category,
		round(sum(price + freight_value)::numeric, 0) as revenue,
		count(distinct order_id) as orders_count
	from segment_enriched_order_items
	group by customer_segment, category
),
segment_category_filtered as (
	select
		customer_segment,
		category,
		revenue,
		orders_count
	from segment_category_aggregated
	where orders_count >= 100	-- keep only categories with sufficient volume to avoid noisy comparisons
),
segment_category_pct as (
	select
		customer_segment,
		category,
		revenue,
		orders_count,
		round((100.0 * revenue / sum(revenue) over (partition by customer_segment)), 2) as pct_segment_revenue_share
	from segment_category_filtered
),
segment_category_metrics as (
	select
		category,
		sum(case when customer_segment = 'CHAMPION' then pct_segment_revenue_share else 0 end) as pct_revenue_champion,
		sum(case when customer_segment = 'BIG SPENDER' then pct_segment_revenue_share else 0 end) as pct_revenue_big_spender
	from segment_category_pct
	group by category
),
segment_category_metrics_diff as (
	select
		category,
		pct_revenue_champion,
		pct_revenue_big_spender,
		round(pct_revenue_champion - pct_revenue_big_spender, 2) as difference_pct,
		round(abs(pct_revenue_champion - pct_revenue_big_spender), 2) as abs_difference_pct
	from segment_category_metrics
)
select * from segment_category_metrics_diff
order by abs_difference_pct desc;
