-- RFM segmentation logic is reused intentionally to keep each analysis file self-contained.

-- Scoring logic:
-- - Recency score: NTILE(5) on recency_days in descending order, so higher scores mean more recent customers.
-- - Frequency score: manually assigned from observed order frequency to avoid weak distribution from NTILE on low integer values.
-- - Monetary score: NTILE(5) on total customer revenue in ascending order, so higher scores mean higher customer value.
-- Segments are business-oriented and designed for exploratory analysis rather than strict CRM production use.


-- Purpose: build the base RFM table at customer level using customer_unique_id as the real customer identifier
select 
	c.customer_unique_id,
	max(o.order_purchase_timestamp)::date as last_order_date,
	date '2018-10-17' - max(o.order_purchase_timestamp)::date as recency_days,
	count(distinct o.order_id) as frequency,
	round(sum(oi.price + oi.freight_value)::numeric, 0) as monetary
from orders o
join customers c on o.customer_id = c.customer_id 
join order_items oi on o.order_id = oi.order_id
group by c.customer_unique_id;



-- Purpose: assign business-oriented RFM segments using recency and monetary quintiles plus a manual frequency score
with customer_rfm_base as (
	select 
		c.customer_unique_id,
		max(o.order_purchase_timestamp)::date as last_order_date,
		date '2018-10-17' - max(o.order_purchase_timestamp)::date as recency_days,
		count(distinct o.order_id) as frequency,
		round(sum(oi.price + oi.freight_value)::numeric, 0) as monetary
	from orders o
	join customers c on o.customer_id = c.customer_id 
	join order_items oi on o.order_id = oi.order_id
	group by c.customer_unique_id
),
customer_rfm_scores_base as (
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
customer_rfm_scores as (
	select 
		customer_unique_id,
		recency_score,
		frequency_score,
		monetary_score,
		concat(recency_score, frequency_score, monetary_score) as rfm,
		recency_score + frequency_score + monetary_score as sum_rfm		
	from customer_rfm_scores_base
),
customer_segmentation as (
	select
		customer_unique_id,
		recency_score,
		frequency_score,
		monetary_score,
		rfm,
		sum_rfm,
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
)
select * from customer_segmentation;



-- Purpose: summarize customer segments by size, revenue contribution, and average customer revenue
with customer_rfm_base as (
	select 
		c.customer_unique_id,
		max(o.order_purchase_timestamp)::date as last_order_date,
		date '2018-10-17' - max(o.order_purchase_timestamp)::date as recency_days,
		count(distinct o.order_id) as frequency,
		round(sum(oi.price + oi.freight_value)::numeric, 0) as monetary
	from orders o
	join customers c on o.customer_id = c.customer_id 
	join order_items oi on o.order_id = oi.order_id
	group by c.customer_unique_id
),
customer_rfm_scores_base as (
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
customer_rfm_scores as (
	select 
		customer_unique_id,
		recency_score,
		frequency_score,
		monetary_score,
		concat(recency_score, frequency_score, monetary_score) as rfm,
		recency_score + frequency_score + monetary_score as sum_rfm		
	from customer_rfm_scores_base
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
segment_revenue_summary as (
	select
		cs.customer_segment,
		count(distinct cs.customer_unique_id) as customer_count,
		round(sum(rs.monetary), 0) as total_revenue,
		round(avg(rs.monetary), 0) as avg_customer_revenue
	from customer_rfm_base rs
	join customer_segmentation cs on rs.customer_unique_id = cs.customer_unique_id
	group by cs.customer_segment
),
segment_revenue_summary_pct as (
	select
		customer_segment,
		customer_count,
		total_revenue,
		avg_customer_revenue,
		round(100.0 * customer_count / sum(customer_count) over (), 1) as customer_share_pct,
		round(100.0 * total_revenue / sum(total_revenue) over (), 1) as revenue_share_pct
	from segment_revenue_summary
)
select * from segment_revenue_summary_pct
order by total_revenue desc, customer_count desc;