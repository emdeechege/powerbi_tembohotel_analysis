-- ==========================================================
-- ======= PART A - DDL ==============================

CREATE SCHEMA IF NOT EXISTS tembo_hotel;

SET search_path TO tembo_hotel;


CREATE TABLE IF NOT EXISTS bookings_staging (
    booking_id          TEXT,  
    guest_name          TEXT,
    guest_phone         TEXT,  
    guest_city          TEXT,
    guest_nationality   TEXT,  
    room_no             TEXT,
    room_type           TEXT,  
    room_rate_per_night TEXT,
    check_in_date       TEXT,  
    check_out_date      TEXT,
    nights_stayed       TEXT,  
    staff_name          TEXT,
    staff_department    TEXT,  
    staff_salary        TEXT,
    payment_method      TEXT,  
    booking_status      TEXT,
    total_amount        TEXT,  
    service_used        TEXT,
    service_price       TEXT,  
    guest_rating        TEXT
);

copy bookings_staging
from 'C:\Users\Public\Documents\bookings_staging.csv' --> Copy path to public where postgresql is allowed or use import data from schema UI
delimiter ','
csv header;

select * from bookings_staging;

select count(*) from bookings_staging;

-- ==========================================
-- ======PART B Audit queries ======================

-- Audit 1 - guest name problems 
select distinct  guest_name from bookings_staging limit 40;
-- we have CAPS need to fix the casing - INITCAP
-- we have names in lowercase - 

-- Audit 2 - room type distinct values
select distinct  room_type, count(*) as count
from bookings_staging group by room_type order by room_type;
/* Expected values: Standard, Deluxe,Suite, Penthouse)
 * dirty values - DLX, Std, standard, deluxe
 * 
 * */
	
-- Audit 3 - payment method 
select distinct  payment_method from bookings_staging;
-- expected - Mpesa , Card, Bank Transfer , Cash


-- Audit 4 - booking status
select distinct  booking_status from bookings_staging;

-- Audit 5 - phone, city
-- phone 
-- Null or empty string
select guest_name, count(*) from bookings_staging 
where guest_phone is null or trim(guest_phone) = ''
group by guest_name;



-- phone 
select booking_id, guest_phone from bookings_staging
where guest_phone like '+254%' or guest_phone like '%-%';

-- city
select distinct 
	case
		when trim(guest_city) ='Thikax' then 'Thika'
		else initcap(trim(guest_city))
	end as guestcity_
from bookings_staging;

select guest_city, count(*) as city_guests  from bookings_staging
group by guest_city 
order by city_guests desc;

-- Audit 6 - Ratings 
select booking_id, guest_name , guest_rating from bookings_staging 
where 
	trim(guest_rating) not in ('1', '2', '3', '4', '5') or 
	trim(guest_rating) = '';

-- Audit 7 - Date Format problems
select booking_id, check_in_date, check_out_date 
from bookings_staging 
where check_in_date not similar to '[0-9]{4}-[0-9]{2}-[0-9]{2}';

-- ==================================================
-- ======= Part C - Time to clean data ==============

-- Clean 1 - fix guest name: trim + fix casing - Captalization 
-- ALICE MWANGI - should be -> Alice Mwangi
-- brian otieno  - should be -> Brian Otieno 
update bookings_staging bs 
	set guest_name = trim(initcap(guest_name));


-- Clean 2 - guest phone: remove dashes, fix +254 
-- +254715623803 - 0715623803
-- 07-15-623-803 - 0715623803 
UPDATE bookings_staging
SET guest_phone = TRIM(
	REPLACE(
		REPLACE(guest_phone, '-', ''), '+254', '0'))
WHERE guest_phone LIKE '+254%' OR guest_phone LIKE '%-%' OR guest_phone LIKE '% %';

/* IMPORTANT
regexp_replace('[^0-9]', '', 'g')
'0' || substring(string, 4) --> append 0, after removing first 4 characters of the string
CASE 
    WHEN REGEXP_REPLACE(guest_phone, '[^0-9]', '', 'g') LIKE '254%' 
    THEN '0' || SUBSTRING(REGEXP_REPLACE(guest_phone, '[^0-9]', '', 'g') FROM 4)
    ELSE REGEXP_REPLACE(guest_phone, '[^0-9]', '', 'g')
END 
*/

-- Clean 3 - guest city: typos, casing , empty (Unknown)
update bookings_staging bs 
	set guest_city = case
		when trim(initcap(guest_city)) = 'Thikax' then 'Thika'
		else trim(initcap(guest_city))
	end; 

-- Fix nationality
update bookings_staging bs 
	set guest_nationality = trim(initcap(guest_nationality))
	where guest_nationality != (initcap(guest_nationality);



-- Clean 4 - Date formats 
-- 2026-04-28 
/*UPDATE bookings_staging
SET check_in_date = TO_DATE(
    CASE 
        -- Check if the middle part (index 2) is > 12
        WHEN SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 2)::INT > 12 THEN
            -- Format is MM-DD-YYYY. Swap Day and Month to make DD-MM-YYYY
            -- Day = Part 2, Month = Part 1, Year = Part 3 (expanded if needed)
            SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 2) || '-' || 
            SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 1) || '-' || 
            CASE 
                WHEN LENGTH(SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 3)) = 2 
                THEN '20' || SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 3)
                ELSE SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 3)
            END
        ELSE
            -- Format is likely DD-MM-YYYY. Just normalize year and separators.
            SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 1) || '-' || 
            SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 2) || '-' || 
            CASE 
                WHEN LENGTH(SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 3)) = 2 
                THEN '20' || SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 3)
                ELSE SPLIT_PART(REPLACE(check_in_date, '/', '-'), '-', 3)
            END
    END,
    'DD-MM-YYYY'
)
WHERE check_in_date NOT SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}';

UPDATE bookings_staging
SET check_out_date = TO_DATE(
    CASE 
        WHEN SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 2)::INT > 12 THEN
            SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 2) || '-' || 
            SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 1) || '-' || 
            CASE WHEN LENGTH(SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 3)) = 2 
                THEN '20' || SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 3)
                ELSE SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 3)
            END
        ELSE
            SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 1) || '-' || 
            SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 2) || '-' || 
            CASE WHEN LENGTH(SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 3)) = 2 
                THEN '20' || SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 3)
                ELSE SPLIT_PART(REPLACE(check_out_date, '/', '-'), '-', 3)
            END
    END,
    'DD-MM-YYYY'
)
WHERE check_out_date NOT SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}'; */

---- Fix CHECK OUT dates ---------------
-- 1. Fix already clean-looking slash dates that are clearly US format
-- Example: 1/13/2024 -> 2024-01-13
--SELECT 
--  TO_DATE('1/13/2024', 'mm/dd/YYYY') AS parsed_date;
--select SPLIT_PART('1/13/2024', '/', 1)::INT > 12;

UPDATE bookings_staging
set check_in_date = TO_DATE(check_in_date, 'MM/DD/YYYY')::TEXT
WHERE check_in_date LIKE '%/%'
  AND SPLIT_PART(check_in_date, '/', 2)::INT > 12;

-- 2. Fix clearly day-first slash dates
-- Example: 15/01/2024 -> 2024-01-15
-- SELECT 
--  TO_DATE('15/01/2024', 'DD/MM/YYYY') AS parsed_date,
--   TO_DATE('15/01/2024', 'DD/MM/YYYY')::TEXT AS text_output;

UPDATE bookings_staging
SET check_in_date = TO_DATE(check_in_date, 'DD/MM/YYYY')::TEXT
WHERE check_in_date LIKE '%/%'
  AND SPLIT_PART(check_in_date, '/', 1)::INT > 12;

-- 3. Fix remaining slash dates
-- Assumption: remaining slash dates are DD/MM/YYYY
-- Example: 1/6/2024 -> 2024-06-01
--select to_date('1/6/2024', 'dd/mm/yyyy') as parsed_date;

UPDATE bookings_staging
SET check_in_date = TO_DATE(check_in_date, 'DD/MM/YYYY')::TEXT
WHERE check_in_date LIKE '%/%';

-- 4. Fix dashed DD-MM-YYYY dates
-- Example: 17-11-2024 -> 2024-11-17
UPDATE bookings_staging
SET check_in_date = TO_DATE(check_in_date, 'DD-MM-YYYY')::TEXT
WHERE check_in_date NOT SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}';

---- Fix CHECK OUT dates -------------
-- 1. Fix already clean-looking slash dates that are clearly US format
-- Example: 1/13/2024 -> 2024-01-13
UPDATE bookings_staging
set check_out_date = TO_DATE(check_out_date, 'MM/DD/YYYY')::TEXT
WHERE check_out_date LIKE '%/%'
  AND SPLIT_PART(check_out_date, '/', 2)::INT > 12;

-- 2. Fix clearly day-first slash dates
-- Example: 15/01/2024 -> 2024-01-15
UPDATE bookings_staging
SET check_out_date = TO_DATE(check_out_date, 'DD/MM/YYYY')::TEXT
WHERE check_out_date LIKE '%/%'
  AND SPLIT_PART(check_out_date, '/', 1)::INT > 12;

-- 3. Fix remaining slash dates
-- Assumption: remaining slash dates are DD/MM/YYYY
-- Example: 1/6/2024 -> 2024-06-01
UPDATE bookings_staging
SET check_out_date = TO_DATE(check_out_date, 'DD/MM/YYYY')::TEXT
WHERE check_out_date LIKE '%/%';

-- 4. Fix dashed DD-MM-YYYY dates
-- Example: 17-11-2024 -> 2024-11-17
UPDATE bookings_staging
SET check_out_date = TO_DATE(check_out_date, 'DD-MM-YYYY')::TEXT
WHERE check_out_date NOT SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}';


-- Clean 5 - roomtype: abbreviations and lowercase 
-- Standard, Deluxe, Suite, Penthouse
update bookings_staging bs 
	set room_type = case
		when trim(initcap(room_type)) = 'Std' then 'Standard'
		when trim(initcap(room_type)) = 'Dlx' then 'Deluxe'
		else trim(initcap(room_type))
	end; 

-- Clean 6 - Payment method and booking_status , casing 
update bookings_staging
	set payment_method = 'M-Pesa'
	where payment_method in ('Mpesa', 'M-pesa', 'mpesa');

update bookings_staging bs 
	set booking_status = trim(initcap(booking_status));

-- clean 7 - total amount and staff salary (strip KES, commas, cast to number)
-- Set empty total_amount to NULL
UPDATE bookings_staging 
SET total_amount = NULL
WHERE TRIM(total_amount) = '';

update bookings_staging
set
	total_amount = REGEXP_REPLACE(total_amount, '[^0-9.]', '', 'g')::numeric,
	staff_salary = REGEXP_REPLACE(staff_salary, '[^0-9.]', '', 'g')::numeric
where
	total_amount is not null
	or staff_salary is not null;

-- select guest_rating from bookings_staging
-- WHERE guest_rating NOT IN ('1','2','3','4','5')
--    OR TRIM(guest_rating) = '';

UPDATE bookings_staging
SET guest_rating = NULL
WHERE guest_rating NOT IN ('1','2','3','4','5')
   OR TRIM(guest_rating) = '';


-- clean 8 - guest rating: invalid values - null 

-- 1. VERIFY what will be deleted
SELECT booking_id, nights_stayed, 
       NULLIF(REGEXP_REPLACE(nights_stayed, '[^0-9-]', '', 'g'), '')::INTEGER as numeric_val
FROM bookings_staging
WHERE NULLIF(REGEXP_REPLACE(nights_stayed, '[^0-9-]', '', 'g'), '')::INTEGER < 1;

-- clean 9 - Remove exact duplicates 
select booking_id, count(*) from bookings_staging
group by booking_id having count(*) > 1;

DELETE FROM bookings_staging a
USING bookings_staging b
WHERE a.ctid > b.ctid  -- We will keep the row with the highest ctid (the most recently inserted version) and delete all others that share the same booking_id.
  AND a.booking_id = b.booking_id;

-- clean 10 - figure out other fixes you need to do 
-- Auto fill missing salary where name and department are similar
update bookings_staging
set staff_salary = (
	select round(AVG(staff_salary::numeric), 0)
	from bookings_staging b
	where
		b.staff_name = bookings_staging.staff_name
		and b.staff_department = bookings_staging.staff_department
		and b.staff_salary is not null
	)
where
	staff_salary is null;

select * from bookings_staging bs ;

-- Find out how to calculate Total amount where missing
SELECT 
    bs.room_rate_per_night, 
    bs.nights_stayed, 
    bs.service_used, 
    bs.service_price, 
    bs.total_amount, -- This is NULL
    -- The Calculated "Proposed Total"
    (bs.room_rate_per_night::numeric * bs.nights_stayed::numeric) 
    + COALESCE(bs.service_price::numeric, 0) as proposed_total
FROM bookings_staging bs 
WHERE bs.total_amount IS NULL;

-- 11. Update Total Amount
UPDATE bookings_staging
SET total_amount = (
    room_rate_per_night::numeric * nights_stayed::numeric) + COALESCE(service_price::numeric, 0)
WHERE total_amount IS NULL;

-- 12. Clean 'service_used'
UPDATE bookings_staging
SET service_used = 'No Service'
WHERE service_used IS NULL;

-- 13. Clean 'service_price'
-- Option A: Set to 0 (Best for math)
UPDATE bookings_staging
SET service_price = 0
WHERE service_price IS NULL;


-- ========== PART D ==========================
-- Create production table and load clean data .

CREATE TABLE IF NOT EXISTS bookings (
    booking_id          VARCHAR(10) PRIMARY KEY,
    guest_name          VARCHAR(100),
    guest_city          VARCHAR(60),
    room_no             VARCHAR(5),
    room_rate_per_night NUMERIC(10,2),
    check_in_date       DATE,
    check_out_date      DATE,
    nights_stayed       INTEGER,
    staff_name          VARCHAR(100),
    staff_salary        NUMERIC(10,2),
    booking_status      VARCHAR(20),
    service_used        VARCHAR(60),
    guest_rating        INTEGER,
    guest_phone         VARCHAR(15),
    guest_nationality   VARCHAR(60),
    room_type           VARCHAR(20),
    staff_department    VARCHAR(50),
    payment_method      VARCHAR(20),
    total_amount        NUMERIC(12,2),
    service_price       NUMERIC(10,2)
);
		

INSERT INTO bookings (
    booking_id, 
    guest_name, 
    guest_city, 
    room_no, 
    room_rate_per_night,
    check_in_date, 
    check_out_date, 
    nights_stayed, 
    staff_name, 
    staff_salary,
    booking_status, 
    service_used, 
    guest_rating, 
    guest_phone, 
    guest_nationality,
    room_type, 
    staff_department, 
    payment_method, 
    total_amount, 
    service_price
)
SELECT 
    booking_id, 
    guest_name, 
    guest_city, 
    room_no, 
    room_rate_per_night::NUMERIC,
    TO_DATE(check_in_date, 'YYYY-MM-DD'),   -- Explicit Date Cast
    TO_DATE(check_out_date, 'YYYY-MM-DD'),  -- Explicit Date Cast
    nights_stayed::INTEGER, 
    staff_name, 
    staff_salary::NUMERIC, 
    booking_status, 
    service_used, 
    guest_rating::INTEGER, 
    guest_phone, 
    guest_nationality,
    room_type, 
    staff_department, 
    payment_method, 
    total_amount::NUMERIC, 
    service_price::NUMERIC
FROM bookings_staging
WHERE 
    booking_id IS NOT NULL
    AND check_in_date IS NOT NULL
    AND check_out_date IS NOT NULL
    AND room_type IS NOT NULL
    AND nights_stayed IS NOT NULL
    AND nights_stayed::INTEGER > 0
    AND room_rate_per_night IS NOT NULL
    AND room_rate_per_night::NUMERIC > 0;



select * from bookings;

-- =================Analysis=====================================
-- ### 1. Revenue Analysis

-- Total Revenue by Month**
-- Groups revenue by Year and Month to see trends.*
-- WHERE booking_status = 'Checked Out' will be attached to most querries for accuracy of the analysis
select 
    to_char(check_in_date, 'yyyy-mm') as month,
    sum(total_amount) as total_revenue
from bookings
where booking_status = 'Checked Out'
group by to_char(check_in_date, 'yyyy-mm')
order by month;


-- B. Total Revenue by Room Type
-- Identifies which room category generates the most income.

select 
    room_type,
    count(*) as total_bookings,
    sum(total_amount) as total_revenue,
    round(avg(total_amount), 2) as avg_revenue_per_booking,
    round(avg(guest_rating), 1) as avg_guest_rating
from bookings
where booking_status = 'Checked Out'
group by room_type
order by total_revenue desc;

-- Total Revenue by Payment Method
-- Shows which payment methods are most popular and profitable.

select 
    payment_method,
    count(*) as num_bookings,
    sum(total_amount) as total_revenue
from bookings
where booking_status = 'Checked Out'
group by payment_method
order by total_revenue desc;

-- 1D: Revenue pivot - payment methods side by side
select
    TO_CHAR(check_in_date, 'YYYY-MM') as month,
    SUM(CASE WHEN payment_method = 'M-Pesa' THEN total_amount ELSE 0 END) AS mpesa_revenue,
    SUM(CASE WHEN payment_method = 'Cash' THEN total_amount ELSE 0 END) AS cash_revenue,
    SUM(CASE WHEN payment_method = 'Card' THEN total_amount ELSE 0 END) AS card_revenue,
    SUM(CASE WHEN payment_method = 'Bank Transfer' THEN total_amount ELSE 0 END) AS bank_revenue
from bookings 
where booking_status = 'Checked Out'
group by to_char(check_in_date, 'YYYY-MM')
order by month desc;

--  Occupancy Analysis
-- Which room types are booked most? (Avg nights stayed)
-- Combines booking count and average duration to find popularity.

-- 2A: Occupancy by room type
SELECT
    room_type,
    COUNT(*) AS total_bookings,
    SUM(nights_stayed) AS total_nights_stayed,
    ROUND(AVG(nights_stayed), 1) AS avg_nights_per_booking,
    SUM(total_amount) AS total_revenue,
    ROUND(SUM(total_amount) / SUM(nights_stayed), 2) AS revenue_per_night
FROM bookings
WHERE booking_status = 'Checked Out'
GROUP BY room_type
ORDER BY total_revenue DESC;

-- 2B: Occupancy by month
SELECT
    TO_CHAR(check_in_date, 'YYYY-MM') AS month,
    COUNT(*) AS total_bookings,
    SUM(nights_stayed) AS total_nights_stayed
FROM bookings
WHERE booking_status = 'Checked Out'
GROUP BY TO_CHAR(check_in_date, 'YYYY-MM')
ORDER BY total_nights_stayed DESC;


-- 2C: Average stay by guest city
SELECT
    guest_city,
    ROUND(AVG(nights_stayed), 1) AS avg_nights_stayed,
    ROUND(AVG(total_amount), 2) AS avg_total_spent,
    COUNT(*) AS num_bookings
FROM bookings
WHERE booking_status = 'Checked Out'
GROUP BY guest_city
ORDER BY avg_nights_stayed DESC;


-- 3A: Top 10 guest cities
SELECT
    guest_city,
    COUNT(*) AS num_guests,
    SUM(total_amount) AS total_revenue,
    ROUND(AVG(guest_rating), 1) AS avg_rating
FROM bookings
WHERE booking_status = 'Checked Out'
GROUP BY guest_city
ORDER BY num_guests DESC
LIMIT 10;

-- 3B: Guest satisfaction by room type
SELECT
    room_type,
    ROUND(AVG(guest_rating), 1) AS avg_rating,
    COUNT(CASE WHEN guest_rating >= 4 THEN 1 END) AS happy_guests,
    COUNT(CASE WHEN guest_rating IS NOT NULL THEN 1 END) AS total_rated,
    ROUND(
        COUNT(CASE WHEN guest_rating >= 4 THEN 1 END) * 100.0 / 
        COUNT(CASE WHEN guest_rating IS NOT NULL THEN 1 END), 
        1
    ) AS pct_happy
FROM bookings
WHERE booking_status = 'Checked Out'
GROUP BY room_type
ORDER BY avg_rating DESC;


-- 3C: Repeat guests
SELECT
    guest_name,
    guest_city,
    COUNT(*) AS num_bookings,
    SUM(total_amount) AS total_spent,
    ROUND(AVG(guest_rating), 1) AS avg_rating
FROM bookings
WHERE booking_status = 'Checked Out'
GROUP BY guest_name, guest_city
HAVING COUNT(*) > 1
ORDER BY num_bookings DESC;

-- -- 3D: Sentiment breakdown
WITH sentiment_counts AS (
    SELECT
        CASE 
            WHEN guest_rating >= 4 THEN 'Happy'
            WHEN guest_rating = 3 THEN 'Neutral'
            WHEN guest_rating < 3 THEN 'Unhappy'
            ELSE 'No Rating'
        END AS sentiment,
        COUNT(*) AS count
    FROM bookings
    WHERE booking_status = 'Checked Out'
    GROUP BY sentiment
)
SELECT
    sentiment,
    count,
    ROUND(count * 100.0 / SUM(count) OVER (), 1) AS percentage
FROM sentiment_counts
ORDER BY count DESC;

-- Staff Performance

-- Which staff handled the most bookings?
-- Rank staff by the number of bookings they processed.
-- 4A: Staff booking performance
SELECT
    staff_name,
    staff_department,
    COUNT(*) AS num_bookings,
    SUM(total_amount) AS total_revenue,
    ROUND(AVG(guest_rating), 1) AS avg_guest_rating
FROM bookings
WHERE booking_status = 'Checked Out'
GROUP BY staff_name, staff_department
ORDER BY total_revenue DESC;

-- 4B: Department summary
SELECT
    staff_department,
    COUNT(*) AS total_bookings,
    ROUND(AVG(guest_rating), 1) AS avg_guest_rating,
    SUM(total_amount) AS total_revenue,
    ROUND(AVG(staff_salary), 2) AS avg_salary,
    COUNT(DISTINCT staff_name) AS num_staff
FROM bookings
WHERE booking_status = 'Checked Out'
GROUP BY staff_department
ORDER BY total_revenue DESC;

---- 4C: Staff ranking with window functions
WITH staff_totals AS (
    SELECT
        staff_name,
        staff_department,
        COUNT(*) AS total_bookings,
        SUM(total_amount) AS total_revenue
    FROM bookings
    WHERE booking_status = 'Checked Out'
    GROUP BY staff_name, staff_department
)
SELECT
    staff_name,
    staff_department,
    total_bookings,
    total_revenue,
    RANK() OVER (ORDER BY total_revenue DESC) AS overall_rank,
    RANK() OVER (PARTITION BY staff_department ORDER BY total_revenue DESC) AS dept_rank
FROM staff_totals
ORDER BY total_revenue DESC;


-- 5A: Month-over-month revenue change
WITH monthly_revenue AS (
    SELECT
        TO_CHAR(check_in_date, 'YYYY-MM') AS month,
        SUM(total_amount) AS revenue
    FROM bookings
    WHERE booking_status = 'Checked Out'
    GROUP BY TO_CHAR(check_in_date, 'YYYY-MM')
)
SELECT
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
    revenue - LAG(revenue) OVER (ORDER BY month) AS change_amount,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month)) / 
        LAG(revenue) OVER (ORDER BY month) * 100, 1) AS change_pct
FROM monthly_revenue
ORDER BY month;


-- 5B: Running total of revenue
WITH monthly_revenue AS (
    SELECT
        TO_CHAR(check_in_date, 'YYYY-MM') AS month,
        SUM(total_amount) AS revenue
    FROM bookings
    WHERE booking_status = 'Checked Out'
    GROUP BY TO_CHAR(check_in_date, 'YYYY-MM')
)
SELECT
    month,
    revenue,
    SUM(revenue) OVER (ORDER BY month) AS cumulative_revenue
FROM monthly_revenue
ORDER BY month;

-- 5C: Best and worst performing months
WITH monthly_revenue AS (
    SELECT
        TO_CHAR(check_in_date, 'YYYY-MM') AS month,
        SUM(total_amount) AS revenue,
        RANK() OVER (ORDER BY SUM(total_amount) DESC) AS rank_desc
    FROM bookings
    WHERE booking_status = 'Checked Out'
    GROUP BY TO_CHAR(check_in_date, 'YYYY-MM')
)
SELECT month, revenue, rank_desc
FROM monthly_revenue
WHERE rank_desc <= 3
UNION ALL
SELECT month, revenue, rank_desc
FROM (
    SELECT
        month,
        revenue,
        RANK() OVER (ORDER BY revenue ASC) AS rank_desc
    FROM monthly_revenue
) worst
WHERE rank_desc <= 3
ORDER BY revenue DESC;

-- Cancellations & No-Shows
-- Cancellation Rate per Room Type
-- Calculates the percentage of bookings that were cancelled.
-- 6A: Overall booking status breakdown
SELECT
    booking_status,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage
FROM bookings
GROUP BY booking_status
ORDER BY count DESC;

-- 6B: Cancellation rate by room type
SELECT
    room_type,
    COUNT(*) AS total_bookings,
    COUNT(CASE WHEN booking_status = 'Checked Out' THEN 1 END) AS checked_out,
    COUNT(CASE WHEN booking_status = 'Cancelled' THEN 1 END) AS cancelled,
    COUNT(CASE WHEN booking_status = 'No Show' THEN 1 END) AS no_show,
    ROUND(COUNT(CASE WHEN booking_status = 'Cancelled' THEN 1 END) * 100.0 / COUNT(*),1) AS cancellation_rate_pct
FROM bookings
GROUP BY room_type
ORDER BY cancellation_rate_pct DESC;


-- 6C: Lost revenue from cancellations and no-shows
-- Revenue Lost from Cancellations/No-Shows
-- Estimates the potential revenue lost by summing the `total_amount` of cancelled bookings.
SELECT
    booking_status,
    COUNT(*) AS count,
    SUM(total_amount) AS estimated_revenue_lost
FROM bookings
WHERE booking_status IN ('Cancelled', 'No Show')
GROUP BY booking_status
ORDER BY estimated_revenue_lost DESC;

-- 6D: Cancellations by month
WITH cancellations_by_month AS (
    SELECT
        TO_CHAR(check_in_date, 'YYYY-MM') AS month,
        COUNT(*) AS cancellation_count
    FROM bookings
    WHERE booking_status = 'Cancelled'
    GROUP BY TO_CHAR(check_in_date, 'YYYY-MM')
)
SELECT
    month,
    cancellation_count
FROM cancellations_by_month
ORDER BY cancellation_count DESC;



-- Create a Dashboard View
-- To make these queries reusable, you can create a **View** that combines the key metrics:

CREATE VIEW booking_dashboard AS
SELECT 
    TO_CHAR(check_in_date, 'YYYY-MM') as month,
    room_type,
    COUNT(*) as booking_count,
    SUM(total_amount) as total_revenue,
    round(AVG(total_amount), 2) as avg_booking_value
FROM bookings
GROUP BY 
    TO_CHAR(check_in_date, 'YYYY-MM'), 
    room_type
ORDER BY 
    month, 
    total_revenue DESC;

-- View 1: Monthly revenue summary 
 -- paste your 5A query here (without the LAG — keep it simple for PowerBI)
CREATE OR REPLACE VIEW v_monthly_revenue as 
    SELECT
        TO_CHAR(check_in_date, 'YYYY-MM') AS month,
        SUM(total_amount) AS revenue
    FROM bookings
    WHERE booking_status = 'Checked Out'
    GROUP BY TO_CHAR(check_in_date, 'YYYY-MM');

 -- View 2: Room type performance 
 -- paste your 1B + 2A combined query here 
CREATE OR REPLACE VIEW v_room_performance as
	select 
	    room_type,
	    count(*) as total_bookings,
	    sum(total_amount) as total_revenue,
	    sum(nights_stayed) as total_nights_stayed,
	    round(avg(nights_stayed), 1) as avg_nights_per_booking,
	    round(sum(total_amount) / sum(nights_stayed), 2) as revenue_per_night,
	    round(avg(total_amount), 2) as avg_revenue_per_booking,
	    round(avg(guest_rating), 1) as avg_guest_rating
	from bookings
	where booking_status = 'Checked Out'
	group by room_type
	order by total_revenue desc;

 -- View 3: Staff performance 
-- paste your 4A query here 
 CREATE OR REPLACE VIEW v_staff_performance AS 
	 SELECT
	    staff_name,
	    staff_department,
	    COUNT(*) AS num_bookings,
	    SUM(total_amount) AS total_revenue,
	    ROUND(AVG(guest_rating), 1) AS avg_guest_rating
	FROM bookings
	WHERE booking_status = 'Checked Out'
	GROUP BY staff_name, staff_department
	ORDER BY total_revenue DESC;
 
 -- View 4: Guest city summary 
-- paste your 3A query here 
 CREATE OR REPLACE VIEW v_guest_insights AS 
	select
	    guest_city,
	    count(*) as num_guests,
	    sum(total_amount) as total_revenue,
	    round(avg(guest_rating), 1) as avg_rating
	from bookings
	where booking_status = 'Checked Out'
	group by guest_city
	order by num_guests desc
	limit 10;
 
 -- Bonus View: Cancellation analysis (from bookings table) 
 -- paste your 6B query here 
CREATE OR REPLACE VIEW v_cancellation_analysis as
	select
	    room_type,
	    count(*) AS total_bookings,
	    count(case when booking_status = 'Checked Out' then 1 end) as checked_out,
	    count(case when booking_status = 'Cancelled' then 1 end) as cancelled,
	    count(case when booking_status = 'No Show' then 1 end) as no_show,
	    round(count(case when booking_status = 'Cancelled' then 1 end) * 100.0 / COUNT(*),1) as cancellation_rate_pct
	from bookings
	group by room_type
	order by cancellation_rate_pct desc;

--Verify all your views work 
select * from v_monthly_revenue   limit 5; 
select * from v_room_performance  limit 5; 
select * from v_staff_performance limit 5; 
select * from v_guest_insights    limit 5; 
 
--Add Indexes - Before Power BI Connection 
-- 
--Add indexes on the columns most commonly used in WHERE and GROUP BY. This makes both SQL 
--queries and Power BI refresh faster. 
 -- Index on check_in_date (used in every monthly query) 
CREATE INDEX idx_bookings_checkin ON bookings (check_in_date); 
 -- Index on room_type (used in room analysis queries) 
CREATE INDEX idx_bookings_roomtype ON bookings (room_type); 
-- Index on booking_status (used in cancellation queries) 
CREATE INDEX idx_bookings_status ON bookings (booking_status); 
-- Index on staff_name (used in staff performance queries) 
CREATE INDEX idx_bookings_staff ON bookings (staff_name); 
-- Index on guest_city (used in guest insight queries) 
CREATE INDEX idx_bookings_guestcity  ON bookings (guest_city); 
-- Verify all your indexes were created 
SELECT 
	tablename, 
	indexname 
FROM pg_indexes 
WHERE schemaname = 'tembo_hotel';


