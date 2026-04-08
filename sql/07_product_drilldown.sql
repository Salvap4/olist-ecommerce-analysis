-- Note: Olist reviews are linked to orders, not individual products.
-- Category-level experience metrics therefore use order reviews as a proxy.

-- RFM segmentation logic reused intentionally to keep each analysis file self-contained


-- Purpose: inspect review-level feedback for a high-revenue low-rated product inside the problematic category
with last_review as (
	select
		review_id,
		order_id,
		review_score,
		review_comment_message
	from (
		select
			review_id,
			order_id,
			review_score,
			review_comment_message,
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
		lr.review_id,
		lr.review_score,
		lr.review_comment_message,
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
problem_product_high_value as (
	select
		oicb.review_id,
		cs.customer_segment,
		oicb.review_score,
		oicb.review_comment_message
	from order_item_customer_base oicb
	join customer_segmentation cs on oicb.customer_unique_id = cs.customer_unique_id 
	where
		cs.customer_segment in ('CHAMPION', 'BIG SPENDER') and
		oicb.product_id = '404a57563d487aecbc2b1a01d9b89aab'	-- Selected product after reviewing revenue and satisfaction metrics within bed_bath_table
)
select * from problem_product_high_value
order by review_score asc, review_id asc;




-- Purpose: classify review comments into issue categories to identify the main root causes behind poor customer experience
with last_review as (
	select
		review_id,
		order_id,
		review_score,
		review_comment_message
	from (
		select
			review_id,
			order_id,
			review_score,
			review_comment_message,
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
		lr.review_id,
		lr.review_score,
		lr.review_comment_message,
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
problem_product_high_value as (
	select
		oicb.review_id,
		cs.customer_segment,
		oicb.review_score,
		oicb.review_comment_message
	from order_item_customer_base oicb
	join customer_segmentation cs on oicb.customer_unique_id = cs.customer_unique_id 
	where
		cs.customer_segment in ('CHAMPION', 'BIG SPENDER') and
		oicb.product_id = '404a57563d487aecbc2b1a01d9b89aab'	-- Selected product after reviewing revenue and satisfaction metrics within bed_bath_table
),
problem_product_issue_classification as (
	select 
		review_id,
		customer_segment,
		review_score,
		review_comment_message,
		case 
			when review_comment_message is null then 'no_comment'
			when review_id = 'bdc093c67f789f79796d70955bc44113' then 'wrong_size_or_dimensions'
			when review_id = '10501b9e86af47dc21f094d7378f9d89' then 'delivery_issue' 
			when review_id = 'fc5c31764fc9ebd841881d9801043e7e' then 'wrong_size_or_dimensions'
			when review_id = '7b2ae7a7b8930d783c4cd39d1033f431' then 'misleading_description_or_material'
			when review_id = '8ef3e8fcb7d8d687fe1afeb98a711792' then 'wrong_item_received'
			when review_id = '3d5feea08877091be2ca9fb2d6f8bda9' then 'poor_quality'
			when review_id = '6d44a7b4984b8f41a034f6df379c6fc6' then 'poor_quality'
			when review_id = '557fd09b23ce7fbd63aa23373c61e96b' then 'poor_quality'
			when review_id = '35f6c22ed1bdb272d61b168bef1d3d62' then 'poor_quality'
			when review_id = '96fa92cc9788b8f11a42b9f3e82fae80' then 'positive_or_no_issue'
			when review_id = 'ad18146f7c653a0e108a0634a7483842' then 'positive_or_no_issue'
			when review_id = '6700c55e0a9a5c133625336faad5612d' then 'positive_or_no_issue'
			when review_id = 'f5baab6749daffff9b27b4c2d845f49a' then 'delivery_issue'
			when review_id = '40cc813a3c3ee0d540bef0dfb74ce7ea' then 'misleading_description_or_material'
			else 'unclassified'
		end as issue_category
	from problem_product_high_value
),
review_metrics as (
	select 
		issue_category,
		round(avg(review_score)::numeric, 2) as avg_review_score,
		count(review_id) as review_count
	from problem_product_issue_classification
	group by issue_category
),
review_pct as (
	select 
		issue_category,
		avg_review_score,
		review_count,
		round((100.0 * review_count / sum(review_count) over ())::numeric, 2) as pct_of_total_reviews
	from review_metrics
)
select * from review_pct
order by review_count desc, avg_review_score asc;