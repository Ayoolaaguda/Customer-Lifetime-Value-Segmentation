--create table in the schema
CREATE TABLE "Nexa_Sat".nexa_sat(
	Customer_id VARCHAR(50),
	Gender VARCHAR(10),
	Partner VARCHAR(3),
	Dependents VARCHAR(3),
	Senior_Citizen INT,
	Call_Duration FLOAT,
	Data_Usage FLOAT,
	Plan_Type VARCHAR(20),
	Plan_Level VARCHAR(20),
	Monthly_Bill_Amount FLOAT,
	Tenure_Months INT,
	Multiple_Lines VARCHAR(3),
	Tech_Support VARCHAR(3),
	Churn INT);


--Confirm current schema
Select current_schema();

--Set path for queries
SET search_path to "Nexa_Sat";

--View Data
Select*
From nexa_sat;

--Data Cleaning
--Check for duplicates
Select customer_id,gender,partner,dependents,
	senior_citizen, call_duration, data_usage,
	plan_type, plan_level, monthly_bill_amount,
	tenure_months, multiple_lines, tech_support,
	churn
From nexa_sat
Group by customer_id,gender,partner,dependents,
	senior_citizen, call_duration, data_usage,
	plan_type, plan_level, monthly_bill_amount,
	tenure_months, multiple_lines, tech_support,
	churn
Having Count(*)>1; --this filters out rows that are duplicates

--Check for NULL Values
Select*
From nexa_sat
Where customer_id IS null
OR gender IS null
OR partner IS null
OR dependents IS null
OR senior_citizen IS null
OR call_duration IS null
OR data_usage IS null
OR plan_type IS null
OR plan_level IS null 
OR monthly_bill_amount IS null
OR tenure_months IS null 
OR multiple_lines IS null 
OR tech_support IS null
OR churn IS null;




--Exploratory Data Analysis
--Total No of Users
Select Count (Customer_id) as current_users
From nexa_sat
Where Churn = 0;

--Total NNo of Users By Plan level
Select plan_level, Count(Customer_id) as total_users
From nexa_sat
Where Churn = 0
Group by Plan_level;

--Total Revenue
Select Round(Sum(Monthly_bill_amount::numeric),2) as Revenue
From nexa_sat

--Revenue by Plan Level
Select plan_level, Round(Sum(Monthly_bill_amount::numeric),2) as Revenue
From nexa_sat
Group by plan_level
Order by Revenue;

--Churn count by plan type and plan level
Select plan_level,
		plan_type,
		Count(*) as total_customers,
		Sum(Churn) as churn_count
From nexa_sat
Group by plan_level, plan_type
Order by plan_level;


--Average Tenure
Select plan_level, Round(AVG(tenure_months),2) as Avg_Tenure
From nexa_sat
Group by plan_level;


--No of Customers with Muliple lines
Select multiple_lines, Count(*) as Total_customer
from nexa_sat
Group by multiple_lines;

--No of Senior Citizens Customers by Plan level and Plan Type
Select Senior_Citizen, Plan_Level,Plan_Type, count(Customer_id) as total_customer
From nexa_sat
Where Churn = 0  
Group by Plan_Level, Plan_Type,Senior_citizen
Order by Plan_level;




--MARKETING SEGMENTS
--Create table of existing users
Create Table existing_users as
Select*
From nexa_sat
where churn=0;


--View new table
Select *
From existing_users


--Average Revenue for existing users
Select Round(Avg(monthly_bill_amount::INT),2) as ARPU
From existing_users;

--Add column and Calculate CLV
Alter Table existing_users
Add Column CLV Float;

Update existing_users
Set CLV = monthly_bill_amount *tenure_months;

--View new CLV Column
Select Customer_ID, CLV 
From existing_users

--CLV Score
--montly_bill = 40%, tenure = 30%, call_duration = 10%, data_usage = 10%, premium= 10%
Alter Table existing_users
Add Column CLV_Score Numeric (10,2);

Update existing_users
Set CLV_Score =
			(0.4 * monthly_bill_amount) +
			(0.3 * tenure_months) +
			(0.1 * call_duration) +
			(0.1 * data_usage) +
			(0.1 * Case when Plan_level = 'Premium'
				Then 1 Else 0
				End);

--View new CLV_Score Column
Select Customer_ID, CLV_Score
From existing_users;


--Group Users into Segments based on CLV_Score
Alter Table existing_users
Add Column CLV_Segments VARCHAR;

Update existing_users
Set CLV_Segments =
			Case When CLV_Score > (Select percentile_cont (0.85)
									Within Group (Order by CLV_Score)
									From existing_users) Then 'High Value'
				When CLV_Score >= (Select percentile_cont (0.50)
									Within Group (Order by CLV_Score)
									From existing_users) Then 'Moderate Value'
				When CLV_Score >= (Select percentile_cont (0.25)
									Within Group (Order by CLV_Score)
									From existing_users) Then 'Low Value'
				Else 'Churn Risk'
				End;

--View CLV_Segments
Select  Customer_ID, CLV_Score, CLV_Segments
From existing_users;



--ANALYSING SEGMENTS
--Average bill and tenure per segment
Select CLV_Segments, 
	Round(Avg(Monthly_bill_Amount::INT),2) as Avg_Monthly_Charges,
	Round(Avg(Tenure_months::INT),2) as Avg_Tenure
From existing_users
Group by 1;

--Tech support PCT and multiple lines
Select CLV_segments, 
	Round(AVG(Case When tech_support = 'Yes' Then 1 Else 0 End),2) as Tech_support_pct,
	Round(AVG(Case When multiple_lines = 'Yes' Then 1 Else 0 End),2) as Multiple_lines_Pct
From existing_users
Group by 1
	
--Revenue per segment
Select CLV_Segments, Count(customer_id), 
	Cast(Sum(monthly_bill_amount * tenure_months)as Numeric(10,2)) as Total_Revenue
From existing_users
Group by 1;



--CROSS-SELLING AND UP-SELLING
--Cross-Selling tech support to Senior Citizens
Select Customer_Id
From existing_users
where senior_citizen = 1 -- Senior citizen
AND dependents = 'No' --no children or tech savvy heplers
AND tech_support = 'No' --do not already have this service
AND (CLV_Segments = 'Churn Risk' OR CLV_Segments = 'Low Value')

--Cross-Selling: Multiple lines for partners and dependents
Select Customer_id
From existing_users
Where multiple_lines = 'No'
AND (dependents = 'Yes' OR Partner = 'Yes')
AND plan_level = 'Basic';


--Up-Selling Premium discount for basic users with churn risk
Select Customer_Id
From existing_users
Where CLV_Segments = 'Churn Risk'
AND Plan_level = 'Basic';

--Up-selling:Basic to premium for longer lock period and Higher ARPU
Select Plan_Level, Round(Avg(monthly_bill_amount::INT),2) as Average_bill, 
	Round(Avg(Tenure_months::INT),2) as Average_Tenure			---basic spend more money and have less tenure than premium
From Existing_users
Where CLV_segments = 'High Value'
OR CLV_Segments = 'Moderate Value'
Group by 1;


--Select Customers
Select Customer_id, monthly_bill_amount
From existing_users
Where plan_level = 'Basic'
AND (CLV_segments = 'High Value'OR CLV_Segments = 'Moderate Value')
AND monthly_bill_amount > 150


--CREATE STORED PROCEDURES
--Senior citizens who will be offered tech support
Create Function Tech_support_snr_citizens()
Returns Table (Customer_Id VARCHAR (50))
AS $$
Begin
	Return Query 
	Select eu.Customer_Id
	From existing_users eu
	where eu.senior_citizen = 1 -- Senior citizen
	AND eu.dependents = 'No' --no children or tech savvy heplers
	AND eu.tech_support = 'No' --do not already have this service
	AND (eu.CLV_Segments = 'Churn Risk' OR eu.CLV_Segments = 'Low Value');
END;
$$ Language plpgsql

--At risk customers who will be offered premium discount
Create Function churn_risk_discount()
Returns Table (Customer_Id VARCHAR(50))
AS $$
BEGIN
	RETURN QUERY
	Select eu.Customer_Id
	From existing_users eu
	Where eu.CLV_Segments = 'Churn Risk'
	AND eu.Plan_level = 'Basic';
END;
$$ Language plpgsql

--High usage customers who will be offered premium upgrade
Create Function High_usage_basic_users()
Returns Table (Customer_Id VARCHAR(50))
AS $$
BEGIN
	Return Query
	Select eu.Customer_id
	From existing_users eu
Where eu.plan_level = 'Basic'
AND (eu.CLV_segments = 'High Value'OR eu.CLV_Segments = 'Moderate Value')
AND eu.monthly_bill_amount > 150;
END;
$$ Language plpgsql


--Multiple lines for dependents and partners
Create Function Multiple_lines_dependents_partners()
Returns Table (Customer_Id VARCHAR(50))
AS $$
BEGIN
	Return Query
	Select eu.Customer_id
From existing_users eu
Where eu.multiple_lines = 'No'
AND (eu.dependents = 'Yes' OR eu.Partner = 'Yes')
AND eu.plan_level = 'Basic';
END;
$$ Language plpgsql


--Use Stored Procedures
--Senior Citizens Tech support
Select *
From Tech_support_snr_citizens()
	
--churn risk discount
Select *
From churn_risk_discount();

--High usage basic
Select *
From  High_usage_basic_users();

--Multiple lines
Select *
From Multiple_lines_dependents_partners();




































