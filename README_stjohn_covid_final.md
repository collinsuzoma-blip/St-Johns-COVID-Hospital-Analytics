COVID 19 Hospital Operations Analytics
St Johns Newfoundland SQL Project

Project overview
This project examines COVID 19 operational activity at a fictional hospital located in St Johns Newfoundland using PostgreSQL. The analysis focuses on testing demand patient flow intensive care utilization bed capacity and staffing pressure during the pandemic period.

The project is structured as a portfolio case study to demonstrate SQL data modeling synthetic data generation and analytical querying within a healthcare operations context.

All data used in this project is synthetic and does not represent real patients staff members or hospital records.

Business context
During the COVID 19 pandemic hospitals faced sustained operational pressure. Decision makers required timely insight into testing positivity admissions intensive care utilization bed occupancy and workforce availability in order to manage risk and allocate resources effectively.

This project recreates those challenges by modeling daily hospital operations across emergency medical and intensive care units. The objective is to support analysis related to capacity planning resource allocation and operational resilience during periods of elevated demand.

Database design
The database follows a dimensional modeling approach with daily fact tables.

Date and hospital unit dimension tables provide structure for time based and unit level analysis.

Daily fact tables store COVID testing activity admissions intensive care metrics bed capacity and staffing availability.

This design supports trend analysis aggregation and dashboard oriented reporting.

Time period covered
The dataset includes daily records from March 2020 through December 2022. This time range enables analysis across multiple pandemic waves with varying intensity and operational impact.

Key metrics analyzed
Testing volume and positivity rate
Hospital admissions and discharges
Intensive care and ventilator usage
Average length of stay
Bed occupancy and capacity pressure
Staffing availability and illness related absences

SQL features demonstrated
Relational schema design using primary and foreign keys
Generation of daily time series using generate series
Creation of synthetic data constrained by realistic operational rules
Development of views for executive level analysis and dashboard consumption
Use of aggregate queries for trend and performance evaluation

Views included
Executive summary presenting consolidated COVID metrics
Daily positivity trend
Hospital admissions and intensive care utilization trend
Bed occupancy and capacity pressure
Staffing pressure and workforce gaps

Running the project
Restore the database using the provided PostgreSQL dump file.
Connect to the database using any PostgreSQL client.
Query the views directly or build analytical dashboards on top of them.

Data disclaimer
All data in this project is synthetic and generated exclusively for educational and portfolio purposes.
It does not reflect real hospital operations or real individuals.
The project is intended solely to demonstrate SQL and data analysis skills.

Target audience
This project is intended for reviewers hiring managers and instructors evaluating SQL analytics healthcare data modeling and operational reporting capabilities.

Programmer Anasieze Uzoma
