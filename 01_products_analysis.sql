CREATE OR REPLACE VIEW products_analysis AS

/* join two tables */
WITH base_joined AS (
	SELECT 
	    p.product_name,
	    p.campaign_name,
	    cat.category_name,
	    p.items_viewed,
	    p.items_added_to_cart,
	    p.items_purchased,
	    p.item_revenue
	FROM ga4_products p
	LEFT JOIN (
	    SELECT DISTINCT 
	        product_name, 
	        category_name 
	    FROM ga4_category
	) cat 
	    ON p.product_name = cat.product_name
),



aggregated_products AS(
	SELECT 
	product_name,
	category_name,
	COALESCE(NULLIF(campaign_name, '(not set)'), 'unidentified source') AS campaign_name,
	
	/*compare paid marketing vs free traffic*/
	CASE 
		WHEN campaign_name IN ('Milwaukee-Ogród-Shopping', 'Milwaukee – Narzedzia4you – Search Website traffic-Search-3','PMax | Distar | Sprzedaż | Polska', 'ceneo / referral') 
	    THEN 'Paid Marketing'
		ELSE 'Free source'
	END AS traffic_channel_type,
	
	
	SUM(items_viewed) AS total_viewed,
	SUM(items_added_to_cart) AS total_cart_adds,
	SUM(items_purchased) AS total_purchased,
	SUM(item_revenue) AS total_revenue
	
	FROM base_joined
	
	GROUP BY product_name, category_name, campaign_name, traffic_channel_type
	/*filter out low-traffic items (<10 views) to eliminate statistical noise in conversion rate calculation*/
	HAVING SUM(items_viewed)>=10
)


SELECT 
product_name,
category_name,
campaign_name,
traffic_channel_type,
total_viewed,
total_cart_adds,
total_purchased,
total_revenue,

/*Check if anyone added the item to cart */
CASE 
	WHEN total_cart_adds>0 THEN 1
	ELSE 0
END AS cart_intent,

/*find top products based on sales and conversion, ignoring price*/
ROUND(total_purchased*(total_purchased*1.0/NULLIF(total_viewed,0)),3) AS volume_efficiency_score,

/*rank products by revenue: indside the campaign and overall in the store*/
DENSE_RANK() OVER (PARTITION BY campaign_name ORDER BY total_revenue DESC) AS product_rank_in_campaign,
DENSE_RANK() OVER (PARTITION BY category_name ORDER BY total_revenue DESC) AS product_rank_in_category,
DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS global_revenue_rank

FROM aggregated_products
ORDER BY global_revenue_rank ASC;
