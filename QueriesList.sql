
-- 1st Query using our DB Schema
SELECT p.pt_id, p.prefix, p.first_name,
    p.last_name, pa.allergy_name, 
    t.device_type FROM patient p
    LEFT JOIN tracker t ON p.trck_model_id = t.trck_model_id
    LEFT jOIN pt_allergy pa ON p.pt_id = pa.pt_id
    WHERE p. pt_id = '592';

-- same Query using the initial 2 table structure
SELECT DISTINCT(pt_id), pt_name, allergy, device_type
FROM 
(SELECT d3.pt_id, d3.pt_name, d3.allergy, d1.device_type 
FROM dataset3 d3)
JOIN dataset1 d1 ON d1.model_ = d3.tracker
WHERE d3.pt_id = '591');


-- 2nd Query using our DB Schema
SELECT p.pt_id, p.prefix, p.first_name,
    p.last_name, p.dob, p.medical_condition, pa.allergy_name
    FROM patient p
    JOIN pt_allergy pa ON p.pt_id = pa,pt_id
    WHERE pa.allergy_name IN ('Egg', 'Peanuts')
    AND p.dob > '1990-01-01'
    AND p.prefix = 'Dr.'
    ORDER BY p.pt_id;


-- 3rd Query using our DB Schema
SELECT tc.trck_id, t.model_name, tc.brand_name,
t.device_type, tc.color, tc.display, tc.strap_material,
tc.selling_price FROM trck_spec tc
JOIN tracker t ON tc.trck_model_id = t.trck_model_id 
WHERE t.device_type = 
    (
        SELECT t.device_type FROM tracker t 
        JOIN patient p ON p.trck_model_id = t.trck_model_id
        WHERE p.pt_id = '99995'
    )
    AND tc.color = 'Blue'
    AND tc.selling_price < '20000'
    ORDER BY tc.rating DESC
    LIMIT 5;

-- 3rd Query using the Old Design
SELECT * FROM dataset1 d1
WHERE d1.device_type = (
    SELECT DISTINCT(d1.device_type) FROM
    (
        SELECT d1.device_type FROM dataset3 d3 
        JOIN dataset1 d1 ON d1.model = p.tracker
        WHERE p.pt_id = '99995'
    )
)
AND d1.color ~* 'Blue'
AND d1.selling_price < '20000'
ORDER BY d1.rating DESC
LIMIT 5;


-- 4th Query using our DB Schema
SELECT p.pt_id, p.prefix, p.first_name, p.last_name, p.dob,
p.gender, pa.allergy_name, p.medication, p.last_visit 
FROM patient p
JOIN pt_allergy pa ON p.pt_id = pa.pt_id
WHERE pa..allergy_name IN ('Egg', 'Peanut')
AND p.gender = 'M'
AND p.prefix = 'Dr.'
AND p.dob = < '1975-01-01'
AND p.medication = true
AND p.last_visit < '2022-01-01';

-- 4th Query using the Old Design
SELECT d3.pt_id, d3.pt_name, d3.dob,
d3.gender, d3.allergy, d3.medication, d3.last_visit, 
FROM dataset3 d3
WHERE d3.allergy IN ('Egg', 'Peanut') 
AND d3.gender = 'M'
AND d3.pt_name ~* 'Dr\.'
AND d3.dob < '1975-01-01'
AND d3.medication = 'Yes'
AND d3.last_visit < '2022-01-01';

-- Role Access testing
SET ROLE doctor;
SET ROLE technician;

SELECT * FROM patient;
SELECT * FROM trck_spec;






---------------------------
-- Trim , Uppercase
UPDATE dataset1
SET brand_name =
TRIM(CONCAT (
UPPER(SUBSTRING(brand_name, 1, 1)),
LOWER(SUBSTRING(brand_name, 2, LENGTH(brand_name)))	
))


--CASTING prices into money data type:
SELECT selling_price, 
CAST(REPLACE(selling_price, ',', '') AS MONEY) 
AS money_price
FROM dataset1

UPDATE dataset1
SET original_price = 
REPLACE(original_price, ',', '')

ALTER TABLE dataset1
ALTER column original_price TYPE money USING original_price::money



--For patient table, deleting all titles from name column (PhD, DDS, DVM, MD)
UPDATE dataset3
SET patient_name = 
CASE
WHEN patient_name ~* 'DVM|PhD|DDS|DVM|MD' THEN
REGEXP_REPLACE(patient_name, 'DVM|PhD|DDS|DVM|MD', '', 'g')
ELSE patient_name
END


-- Updating the prefix column for names with prefixes:
UPDATE dataset3
SET prefix = subq.prefix 
FROM (
SELECT patient_name, patient_name ~* '\sV$|\sIV$|\sIII$|\sII$|Dr\.|Mr\.|Ms\.|Mrs\.|Miss\s|Jr\.', 
(REGEXP_MATCHES(patient_name,
'\sV$|\sIV$|\sIII$|\sII$|Dr\.|Mr\.|Ms\.|Mrs\.|Miss\s|Jr\.', 'g'))[1] AS prefix
FROM dataset3
) AS subq
WHERE dataset3.patient_name = subq.patient_name


-- Unique colors table 75:
SELECT *, CASE 
WHEN DIFFERENCE(subb.vcolor, 'BLUE')=4
THEN 'Blue'
WHEN DIFFERENCE(subb.vcolor, 'GRAY')=4
THEN 'Gray'
ELSE subb.vcolor
END AS fcolor
FROM 
(SELECT *, subq.scolor, 
CONCAT(
UPPER(SUBSTRING(subq.scolor, 1, 1)),
LOWER(SUBSTRING(subq.scolor, 2, LENGTH(subq.scolor)))
) AS vcolor
FROM (SELECT *, TRIM(unnest(string_to_array(color, ','))) AS scolor 
FROM dataset1) AS subq) AS subb;


-- For first letter capitalization standard: 
SELECT model_name, brand_name, selling_price, 
original_price, display, rating, strap_material,
avg_battery_life, reviews, color,
    CONCAT(
        UPPER(SUBSTRING(color, 1, 1)),
        LOWER(SUBSTRING(color, 2, LENGTH(color)))
    ) AS capitalized_color
FROM tcolor ORDER BY color)





