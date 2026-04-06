Declare @DateStart date ='2013-01-01'
Declare @DateEnd date ='2013-03-31' 
Declare @TopProductCount int =5
Declare @Country nvarchar(100)='France';

with [all_orders] as (
	select 
	  G.[StateProvinceName], 
	  Cat.[EnglishProductCategoryName], 
	  P.[EnglishProductName] as Product, 
	  F.SalesAmount
	from [dbo].[FactInternetSales] as F 
	inner join [dbo].[DimDate] as D 
	  on D.DateKey=F.OrderDateKey 
	inner join [dbo].[DimCustomer] as C 
	  on F.CustomerKey=C.CustomerKey 
	inner join [dbo].[DimGeography] as G 
	  on G.GeographyKey=C.GeographyKey 
	inner join [dbo].[DimProduct] as P 
	  on P.ProductKey=F.ProductKey 
	inner join [dbo].[DimProductSubcategory] as S 
	  on S.[ProductSubcategoryKey]=P.[ProductSubcategoryKey] 
	inner join [dbo].[DimProductCategory] as Cat 
	  on Cat.ProductCategoryKey=S.ProductCategoryKey 
	where 
	  D.[FullDateAlternateKey] between @DateStart and @DateEnd 
	  and G.[EnglishCountryRegionName]=@Country
),
-- top N products in each category
[top_products] as (
  select 
    EnglishProductCategoryName,
	Product
  from 
  (
	  select
		EnglishProductCategoryName, 
		Product, 
		DENSE_RANK() OVER(PARTITION BY EnglishProductCategoryName ORDER BY SUM(SalesAmount) DESC) AS d_rnk
	  from [all_orders]
	  group by EnglishProductCategoryName, Product
  ) all_top_products
  where d_rnk <= @TopProductCount
),
-- 4 levels for reporting
[agg_rnk_states] as (
        -- all sales
		select 
		  0 as AggLevel,
		  NULL as Category,
		  'ALL PRODUCTS' as DataSlice,
		  StateProvinceName,
		  sum(sum(SalesAmount)) over() as AggSalesAmount,
		  row_number() over(order by sum(SalesAmount) desc) as rn
		from [all_orders]
		group by StateProvinceName
		union all
		-- total sales for every category
		select 
		  1 as AggLevel,
		  EnglishProductCategoryName as Category,
		  '  All ' || EnglishProductCategoryName as DataSlice,
		  StateProvinceName,
		  sum(sum(SalesAmount)) over(partition by EnglishProductCategoryName) as AggSalesAmount,
		  row_number() over(partition by EnglishProductCategoryName order by sum(SalesAmount) desc) as rn
		from [all_orders]
		group by EnglishProductCategoryName, StateProvinceName
		union all
		-- total sales for every top N products
		select 
		  2 as AggLevel,
		  EnglishProductCategoryName as Category,
		  '    Top ' || @TopProductCount || ' ' || EnglishProductCategoryName as DataSlice,
		  StateProvinceName,
		  sum(sum(SalesAmount)) over (partition by EnglishProductCategoryName) as AggSalesAmount,
		  row_number() over(partition by EnglishProductCategoryName order by sum(SalesAmount) desc) as rn
		from [all_orders] a
		where exists 
		(
		  select 1
		  from [top_products] t
		  where 
		    t.EnglishProductCategoryName = a.EnglishProductCategoryName
			and t.Product = a.Product
		)
		group by EnglishProductCategoryName, StateProvinceName
		union all
		-- total sales for top N products
		select 
		  3 as AggLevel,
		  EnglishProductCategoryName as Category,
		  '      ' || Product as DataSlice,
		  StateProvinceName,
		  sum(sum(SalesAmount)) over (partition by EnglishProductCategoryName, Product) as AggSalesAmount,
		  row_number() over(partition by EnglishProductCategoryName, Product order by sum(SalesAmount) desc) as rn
		from [all_orders] a
		where exists 
		(
		  select 1
		  from [top_products] t
		  where 
		    t.EnglishProductCategoryName = a.EnglishProductCategoryName
			and t.Product = a.Product
		)
		group by EnglishProductCategoryName, Product, StateProvinceName
)
select 
  DataSlice,
  AggSalesAmount as SalesAmount,
  [1] as TOP_1_State,
  [2] as TOP_2_State,
  [3] as TOP_3_State,
  [4] as TOP_4_State,
  [5] as TOP_5_State
from 
(
  select 
    AggLevel,
    DataSlice,
	Category,
	AggSalesAmount,
	StateProvinceName,
	rn,
	-- for true sales
	max(case when AggLevel in (0, 1) then AggSalesAmount end) over(partition by Category) TotalAmount
  from [agg_rnk_states]
  where 
    rn <= 5
) src
pivot
(
  max(StateProvinceName)
  for rn in ([1], [2], [3], [4], [5])
) as transp_states
order by TotalAmount desc, AggLevel, SalesAmount desc