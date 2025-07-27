use chinook;
SET SQL_SAFE_UPDATES = 0;

-- Objective questions:

-- 1. Does any table have missing values or duplicates? If yes how would you handle it ?

update employee set reports_to = '0' where reports_to is null and employee_id is not null;

update customer set company = 'NA' where company is null and customer_id is not null;
update customer set fax = 'NA' where fax is null and customer_id is not null;
update customer set phone = 'NA' where phone is null and customer_id is not null;
update customer set state = 'None' where state is null and customer_id is not null;

update track set composer = 'None' where composer is null and track_id is not null;

-- 2. Find the top-selling tracks and top artist in the USA and identify their most famous genres.
-- top selling tracks in USA - top 10

select l.track_id, t.name, sum(i.total) as total_revenue 
from invoice_line l join invoice i on i.invoice_id = l.invoice_id join track t on l.track_id=t.track_id
where billing_country = "USA"
group by l.track_id, t.name
order by total_revenue desc, track_id limit 10;

-- top artist in USA with their most famous genre

with top_artist as (select a.artist_id, a.name, sum(i.total) as total_revenue
from artist a join album al on a.artist_id = al.artist_id
join track t on al.album_id = t.album_id 
join invoice_line l on t.track_id = l.track_id
join invoice i on l.invoice_id= i.invoice_id
where i.billing_country = "USA" 
group by a.artist_id, a.name
order by total_revenue desc)

select a.artist_id, a.name, g.genre_id, g.name, sum(i.total) as total_revenue from genre g
join track t on g.genre_id = t.genre_id
join album al on al.album_id = t.album_id
join artist a on a.artist_id=al.artist_id
join invoice_line il on il.track_id=t.track_id
join invoice i on i.invoice_id = il.invoice_id
where a.artist_id in (select artist_id from top_artist)
and i.billing_country = "USA"
group by a.artist_id, a.name, g.genre_id, g.name
order by total_revenue desc limit 10;

-- checking if invoice country is different from customer country or not

select i.billing_state from invoice i join customer c
on i.customer_id=c.customer_id
where i.billing_state <> c.state;

-- 3. What is the customer demographic breakdown (age, gender, location) of Chinook's customer base?
-- customer base demographic breakdown on age, gender and location-- 

-- based on location

with location_breakdown as(
	select customer_id, concat(first_name, " ", last_name) as full_name, city, coalesce(state, "NA") as state, country
	from customer
	group by country, state, city, customer_id, full_name
	order by country, state, city
)
Select country, count(*) as total_customers from location_breakdown group by country order by total_customers desc;

-- 4. Calculate the total revenue and number of invoices for each country, state, and city
-- total revenue 

-- country-wise

select i.billing_country, sum(il.unit_price*il.quantity) as revenue, count(distinct(i.invoice_id)) as total_orders
from invoice i join invoice_line il on i.invoice_id = il.invoice_id
group by billing_country
order by revenue desc;

-- state-wise

select i.billing_state, sum(il.unit_price*il.quantity) as revenue, count(distinct(i.invoice_id)) as total_orders
from invoice i join invoice_line il on i.invoice_id = il.invoice_id
group by billing_state
order by billing_state;

-- city-wise

select i.billing_city, sum(il.unit_price*il.quantity) as revenue, count(distinct(i.invoice_id)) as total_orders
from invoice i join invoice_line il on i.invoice_id = il.invoice_id
group by billing_city
order by billing_city;

-- 5. Find the top 5 customers by total revenue in each country
-- top 5 customers by total revenue in each country

with total_customers as (
select i.billing_country, concat(c.first_name, " ", c.last_name) as customer_name, sum(i.total) as revenue,
rank() over(partition by billing_country order by sum(i.total) desc) as rnk
from invoice i join invoice_line il on i.invoice_id = il.invoice_id
join customer c on c.customer_id=i.customer_id
group by i.billing_country, c.customer_id, c.first_name, c.last_name
)

select billing_country, customer_name, revenue from total_customers
where rnk<=5
order by billing_country desc, rnk;

-- 6. Identify the top-selling track for each customer
-- top-selling track for each customer

with quantity_sold as (
	select c.customer_id, concat(c.first_name, " ", c.last_name) as Full_Name, t.track_id, t.name, sum(i.total) as revenue, sum(il.quantity) as total_quantity,
	rank() over(partition by c.customer_id order by sum(i.total) desc) as rnk
	from customer c join invoice i on c.customer_id = i.customer_id
	join invoice_line il on il.invoice_id = i.invoice_id
	join track t on t.track_id = il.track_id
	group by c.customer_id, c.first_name, c.last_name, t.track_id, t.name
)
select distinct Full_Name, revenue, total_quantity
from quantity_sold
where rnk = 1
order by revenue desc;

-- 7.	Are there any patterns or trends in customer purchasing behavior (e.g., frequency of purchases, preferred payment methods, average order value)? 
-- 1. Purchase Frequency 

WITH PurchaseFrequency AS (
	SELECT 
		c.customer_id, 
        CONCAT(c.first_name,' ',c.last_name) AS customer_name, 
		COUNT(i.invoice_id) AS total_purchases, 
		MIN(DATE(i.invoice_date)) AS first_purchase_date, 
		MAX(DATE(i.invoice_date)) AS latest_purchase_date,
		ROUND(
			DATEDIFF(MAX(DATE(i.invoice_date)),MIN(DATE(i.invoice_date))) / 
            COALESCE(COUNT(i.invoice_id)-1, 0),0) AS avg_days_bet_purchases
	FROM customer c 
	JOIN invoice i ON c.customer_id = i.customer_id
	GROUP BY 1,2
)

SELECT * FROM PurchaseFrequency
ORDER BY avg_days_bet_purchases, total_purchases DESC;


-- 2. Average Order Value 

WITH CustomerPurchases AS (
	SELECT 
		c.customer_id, concat(c.first_name, " ", c.last_name) as full_name,
		SUM(i.total) AS total_order_value, 
        COUNT(i.invoice_id) AS total_purchases,
        ROUND(AVG(i.total),2) AS avg_order_value
	FROM customer c 
    LEFT JOIN invoice i ON c.customer_id = i.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name
)

SELECT * FROM CustomerPurchases
ORDER BY avg_order_value DESC;


-- 8. What is the customer churn rate?
-- to calculate churn rate

with yearly_customers as (select extract(year from invoice_date) as purchase_year, count(distinct customer_id) as total_customers, 
lag(count(distinct customer_id)) over(order by extract(year from invoice_date)) as past_year_customers from invoice 
group by purchase_year
order by purchase_year)

select purchase_year, total_customers, past_year_customers, (past_year_customers-total_customers) as churned_customers,
case
when past_year_customers is Null then null
else ((past_year_customers-total_customers)/past_year_customers)*100
END as Churn_Rate_percentage
from yearly_customers;

-- 9. Calculate the percentage of total sales contributed by each genre in the USA and identify the best-selling genres and artists.

-- percentage of total sales contributed by each genre in the USA and identify best selling genre and artists

with total_revenue as (select g.genre_id, g.name, sum(i.total) as total_sales_per_genre
from genre g join track t on g.genre_id=t.genre_id
join invoice_line il on t.track_id=il.track_id
join invoice i on i.invoice_id=il.invoice_id
where i.billing_country = "USA"
group by g.genre_id, g.name
order by total_sales_per_genre desc),

percent_total_sales as (select genre_id, name, total_sales_per_genre, 
(total_sales_per_genre/(select sum(i.total) from invoice i
							join invoice_line il on i.invoice_id=il.invoice_id
								where i.billing_country = "USA"))*100 as percent_sales
from total_revenue limit 1
)
-- remove limit 1 for identifying the percentage sales of each genre in USA in above query

-- for best selling genre and artists

select distinct p.genre_id, p.name, a.name as artist_name, total_sales_per_genre from percent_total_sales p join genre g on p.genre_id=g.genre_id
join track t on g.genre_id=t.genre_id join album al on al.album_id=t.album_id
join artist a on a.artist_id = al.artist_id;

-- 10. Find customers who have purchased tracks from at least 3 different+ genres

-- customers who have purchased tracks from at least 3 different+ genres

SELECT 
    c.customer_id,
    CONCAT(first_name, ' ', last_name) AS full_name,
    count(Distinct t.track_id) as total_tracks,
    COUNT(distinct t.genre_id) AS total_genre
FROM
    customer c
        JOIN
    invoice i ON c.customer_id = i.customer_id
        JOIN
    invoice_line il ON i.invoice_id = il.invoice_id
        JOIN
    track t ON il.track_id = t.track_id
        JOIN
    genre g ON t.genre_id = g.genre_id
GROUP BY c.customer_id , c.first_name , c.last_name
HAVING COUNT(DISTINCT t.genre_id) >= 3
ORDER BY total_genre DESC;

-- 11. Rank genres based on their sales performance in the USA

-- Rank genres based on their sales performance in the USA

select g.genre_id, g.name, sum(i.total) as total_sales_per_genre,
rank() over(order by sum(i.total) desc) as rnk
from genre g join track t on g.genre_id=t.genre_id
join invoice_line il on t.track_id=il.track_id
join invoice i on i.invoice_id=il.invoice_id
where i.billing_country = "USA"
group by g.genre_id, g.name
order by total_sales_per_genre desc;

-- 12. Identify customers who have not made a purchase in the last 3 months

-- customers who have not made any purchase in last 3 months

select distinct c.customer_id, concat(c.first_name,  " " , c.last_name) as full_name, i.invoice_date
from customer c join invoice i on c.customer_id=i.customer_id 
where i.invoice_date > date_sub((select max(invoice_date) from invoice), interval 3 month);



-- Subjective Questions

-- 1. Recommend the three albums from the new record label that should be prioritised for advertising and promotion in the USA based on genre sales analysis.

SELECT g.name, a.album_id, a.title, SUM(i.total) AS total_sales
FROM invoice_line il
JOIN track t ON il.track_id = t.track_id
JOIN album a ON t.album_id = a.album_id
JOIN genre g ON t.genre_id = g.genre_id
JOIN invoice i ON il.invoice_id = i.invoice_id
WHERE i.billing_country = 'USA'
GROUP BY g.genre_id, a.album_id, a.title
ORDER BY total_sales DESC;

-- 2. Determine the top-selling genres in countries other than the USA and identify any commonalities or differences.


with top_selling_genre as (SELECT i.billing_country, g.name AS genre_name,
       SUM(i.total) AS genre_sales,
      dense_rank() OVER (PARTITION BY i.billing_country ORDER BY SUM(i.total) DESC) AS genre_rank
FROM invoice i
JOIN invoice_line il ON i.invoice_id = il.invoice_id
JOIN track t ON il.track_id = t.track_id
JOIN genre g ON t.genre_id = g.genre_id
WHERE i.billing_country <> 'USA'
GROUP BY i.billing_country, g.name
ORDER BY i.billing_country, genre_rank), 

country_wise_genre_sales as 
(select  billing_country, genre_name, genre_sales from top_selling_genre order by billing_country, genre_sales desc
)
select genre_name, count(billing_country) as country, sum(genre_sales) as total_sales from country_wise_genre_sales
group by genre_name order by total_sales desc;

-- 3. Customer Purchasing Behavior Analysis: How do the purchasing habits (frequency, basket size, spending amount) of long-term customers differ from those of new customers? What insights can these patterns provide about customer loyalty and retention strategies?

WITH in_invoice AS (
    SELECT invoice_id, COUNT(invoice_line_id) AS items_per_invoice
    FROM invoice_line
    GROUP BY invoice_id
),
invoice_sum AS (
    SELECT invoice_id, SUM(quantity * unit_price) AS invoice_total
    FROM invoice_line
    GROUP BY invoice_id
),
customer_metrics as (SELECT 
    i.customer_id, 
    MIN(i.invoice_date) AS first_purchase, 
    MAX(i.invoice_date) AS last_purchase, 
    COUNT(DISTINCT i.invoice_id) AS total_orders,
    AVG(ii.items_per_invoice) AS avg_basket_size,
    AVG(im.invoice_total) AS avg_spending_per_purchase,
    SUM(im.invoice_total) AS total_amount_spent
FROM invoice i
JOIN in_invoice ii ON i.invoice_id = ii.invoice_id
JOIN invoice_sum im ON i.invoice_id = im.invoice_id
GROUP BY i.customer_id
),
segmented_customers as (
	select *,
	case when datediff(date(last_purchase), date(first_purchase)) > 1100 then "Long-Term Customers"
	Else "Short-Term_Customers"
	End as Customer_Classification
	from customer_metrics 
)
select customer_classification, count(customer_id) as total_customers,
	   avg(total_orders) as avg_orders,
       avg(avg_basket_size) as avg_basket_size, 
       avg(avg_spending_per_purchase) as avg_spending_per_purchase, 
       avg(total_amount_spent) as total_amount_spent
       from segmented_customers
       group by customer_classification;

-- 4. Product Affinity Analysis: Which music genres, artists, or albums are frequently purchased together by customers? How can this information guide product recommendations and cross-selling initiatives?

-- genre purchased together

WITH track_combinations AS (
    SELECT il1.track_id AS track_id_1, il2.track_id AS track_id_2, COUNT(*) AS times_purchased_together
    FROM invoice_line il1
    JOIN invoice_line il2 ON il1.invoice_id = il2.invoice_id AND il1.track_id < il2.track_id
    GROUP BY il1.track_id, il2.track_id
),
genre_combinations AS (
    SELECT t1.genre_id AS genre_id_1, t2.genre_id AS genre_id_2, COUNT(*) AS times_purchased_together
    FROM track_combinations tc
    JOIN track t1 ON tc.track_id_1 = t1.track_id
    JOIN track t2 ON tc.track_id_2 = t2.track_id
    WHERE t1.genre_id <> t2.genre_id
    GROUP BY t1.genre_id, t2.genre_id
)
SELECT g1.name AS genre_1, g2.name AS genre_2, gc.times_purchased_together
FROM genre_combinations gc
JOIN genre g1 ON gc.genre_id_1 = g1.genre_id
JOIN genre g2 ON gc.genre_id_2 = g2.genre_id
ORDER BY gc.times_purchased_together DESC;

-- artist purchased together

WITH track_combinations AS (
    SELECT il1.track_id AS track_id_1, il2.track_id AS track_id_2, COUNT(*) AS times_purchased_together
    FROM invoice_line il1
    JOIN invoice_line il2 ON il1.invoice_id = il2.invoice_id AND il1.track_id < il2.track_id
    GROUP BY il1.track_id, il2.track_id
),
artist_combinations AS (
    SELECT a1.artist_id AS artist_id_1, a2.artist_id AS artist_id_2, COUNT(*) AS times_purchased_together
    FROM track_combinations tc
    JOIN track t1 ON tc.track_id_1 = t1.track_id
    JOIN album al1 ON t1.album_id = al1.album_id
    JOIN artist a1 ON al1.artist_id = a1.artist_id
    JOIN track t2 ON tc.track_id_2 = t2.track_id
    JOIN album al2 ON t2.album_id = al2.album_id
    JOIN artist a2 ON al2.artist_id = a2.artist_id
    WHERE a1.artist_id <> a2.artist_id
    GROUP BY a1.artist_id, a2.artist_id
)
SELECT a1.name AS artist_1, a2.name AS artist_2, ac.times_purchased_together
FROM  artist_combinations ac
JOIN artist a1 ON ac.artist_id_1 = a1.artist_id
JOIN artist a2 ON ac.artist_id_2 = a2.artist_id
ORDER BY ac.times_purchased_together DESC;

-- albums purchased together

WITH track_combinations AS (
    SELECT il1.track_id AS track_id_1, il2.track_id AS track_id_2, COUNT(*) AS times_purchased_together
    FROM invoice_line il1
    JOIN invoice_line il2 ON il1.invoice_id = il2.invoice_id AND il1.track_id < il2.track_id
    GROUP BY il1.track_id, il2.track_id
),
album_combinations AS (
    SELECT al1.album_id AS album_id_1, al2.album_id AS album_id_2, COUNT(*) AS times_purchased_together
    FROM track_combinations tc
    JOIN track t1 ON tc.track_id_1 = t1.track_id
    JOIN album al1 ON t1.album_id = al1.album_id
    JOIN track t2 ON tc.track_id_2 = t2.track_id
    JOIN album al2 ON t2.album_id = al2.album_id
    WHERE al1.album_id <> al2.album_id
    GROUP BY al1.album_id, al2.album_id
)
SELECT al1.title AS album_1, al2.title AS album_2, ac.times_purchased_together
FROM album_combinations ac
JOIN album al1 ON ac.album_id_1 = al1.album_id
JOIN album al2 ON ac.album_id_2 = al2.album_id
ORDER BY ac.times_purchased_together DESC;

-- 5. Regional Market Analysis: Do customer purchasing behaviors and churn rates vary across different geographic regions or store locations? How might these correlate with local demographic or economic factors?

-- yearly revenue per country per year

with revenue_per_country_per_year as (select c.country, extract(year from i.invoice_date) as invoice_year, 
count(distinct c.customer_id) as total_customers, 
sum(quantity*unit_price) as total_revenue, 
round(sum(quantity*unit_price)/count(distinct c.customer_id), 2) as avg_revenue_per_customer,
lag(count(distinct c.customer_id)) over(partition by country order by extract(year from i.invoice_date)) as past_year_customers
from invoice i join invoice_line il on i.invoice_id=il.invoice_id 
join customer c on c.customer_id=i.customer_id
group by country, invoice_year
order by country desc, invoice_year, total_revenue desc)

Select *, 
case 
when past_year_customers is Null then 0
when total_customers > past_year_customers then 0
Else (past_year_customers-total_customers) 
END as churned_customers 
from revenue_per_country_per_year;

-- yearly revenue per city per year

with revenue_per_city_per_year as (select billing_city, extract(year from i.invoice_date) as invoice_year, 
count(distinct customer_id) as total_customers, 
sum(quantity*unit_price) as total_revenue, 
round(sum(quantity*unit_price)/count(distinct customer_id), 2) as avg_revenue_per_customer,
lag(count(distinct customer_id)) over(partition by billing_city order by extract(year from i.invoice_date)) as past_year_customers
from invoice i join invoice_line il on i.invoice_id=il.invoice_id 
group by billing_city, invoice_year
order by billing_city desc, invoice_year, total_revenue desc)

Select *, 
case 
when past_year_customers is Null then 0
Else (past_year_customers-total_customers) 
END as churned_customers 
from revenue_per_city_per_year;

-- 6. Customer Risk Profiling: Based on customer profiles (age, gender, location, purchase history), which customer segments are more likely to churn or pose a higher risk of reduced spending? What factors contribute to this risk ?

SELECT
    c.country,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    COUNT(i.invoice_id) AS total_orders,
    ROUND(SUM(i.total), 2) AS total_revenue,
    ROUND(SUM(i.total)/COUNT(DISTINCT c.customer_id), 2) AS avg_spend_per_customer,
    ROUND(COUNT(i.invoice_id)/COUNT(DISTINCT c.customer_id), 2) AS avg_orders_per_customer
FROM customer c
JOIN invoice i ON c.customer_id = i.customer_id
GROUP BY c.country
ORDER BY total_orders desc;

-- 7. Customer Lifetime Value Modelling: How can you leverage customer data (tenure, purchase history, engagement) to predict the lifetime value of different customer segments? This could inform targeted marketing and loyalty program strategies. Can you observe any common characteristics or purchase patterns among customers who have stopped purchasing?

WITH CustomerTenure AS (
    SELECT 
        c.customer_id, CONCAT(c.first_name,' ', c.last_name) AS customer,
        MIN(i.invoice_date) AS first_purchase_date,
        MAX(i.invoice_date) AS last_purchase_date,
        DATEDIFF(MAX(i.invoice_date), MIN(i.invoice_date)) AS tenure_days,
        COUNT(i.invoice_id) AS purchase_frequency,
        SUM(i.total) AS total_spent
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
    GROUP BY c.customer_id
)

SELECT 
    customer_id,
    customer,
    tenure_days,
    purchase_frequency,
    total_spent,
    ROUND(total_spent / purchase_frequency, 2) AS avg_order_value,
    round(tenure_days / purchase_frequency, 2) as avg_days_bet_orders
FROM CustomerTenure
ORDER BY avg_days_bet_orders desc;

-- 11. Chinook is interested in understanding the purchasing behaviour of customers based on their geographical location. They want to know the average total amount spent by customers from each country, along with the number of customers and the average number of tracks purchased per customer. Write a SQL query to provide this information.

with temp as (
	select c.country, c.customer_id, sum(i.total) as total_amount, count(distinct il.track_id) as total_tracks
	from customer c join invoice i on c.customer_id=i.customer_id
	join invoice_line il on i.invoice_id=il.invoice_id
	group by country, customer_id
)
select country, count(customer_id) as total_customers, round(avg(total_amount),2) as avg_amount_per_country, round(avg(total_tracks),2) as avg_tracks_per_country
from temp
group by country
order by avg_tracks_per_country desc;







