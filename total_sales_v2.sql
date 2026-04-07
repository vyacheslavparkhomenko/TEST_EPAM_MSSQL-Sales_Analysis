Declare @DateStart date ='2013-01-01'
Declare @DateEnd date ='2013-03-31' 
Declare @TopProductCount int =5
Declare @Country nvarchar(100)='France';

with [all_orders] as (
	select 
	  G.[StateProvinceName], 
	  Cat.[ProductCategoryKey],
	  Cat.[EnglishProductCategoryName], 
	  P.[ProductKey],
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
    ProductCategoryKey,
	ProductKey
  from 
  (
	  select
		ProductCategoryKey, 
		ProductKey,
		DENSE_RANK() OVER(PARTITION BY ProductCategoryKey ORDER BY SUM(SalesAmount) DESC) AS d_rnk
	  from [all_orders]
	  group by ProductCategoryKey, ProductKey
  ) all_top_products
  where d_rnk <= @TopProductCount
),
[all_orders_ext] as (
  select 
    a.StateProvinceName,
	a.ProductCategoryKey,
	a.EnglishProductCategoryName,
	a.ProductKey,
	a.Product,
	a.SalesAmount,
	case
	  when t.ProductKey is null then 'N'
	  else 'Y'
	end as flag_top_product
  from all_orders a
  left join top_products t
    on t.ProductKey = a.ProductKey
	and t.ProductCategoryKey = a.ProductCategoryKey
),
[agg_orders_ext] as (
  select
    -- level 7 3 1 0
    GROUPING_ID(ProductCategoryKey, flag_top_product, ProductKey) as AggLevel,
    StateProvinceName,
    case
	  when GROUPING_ID(ProductCategoryKey, flag_top_product, ProductKey) <> 7 then max(EnglishProductCategoryName) 
	end as CategoryName,
	case
	  when GROUPING_ID(ProductCategoryKey, flag_top_product, ProductKey) = 0 then max(Product)	
	end as Product,
	sum(sum(SalesAmount)) over(partition by GROUPING_ID(ProductCategoryKey, flag_top_product, ProductKey), ProductCategoryKey, flag_top_product, ProductKey) as TotalSalesAmount,
	max(flag_top_product)			as flag_top_product,
	row_number() over(partition by GROUPING_ID(ProductCategoryKey, flag_top_product, ProductKey), ProductCategoryKey, ProductKey order by sum(SalesAmount) desc) as rn
  from all_orders_ext
  group by 
    grouping sets 
	(
	  (),
	  (ProductCategoryKey),
	  (ProductCategoryKey, flag_top_product),
	  (ProductCategoryKey, flag_top_product, ProductKey)
	),
	StateProvinceName
  -- level 7 3 (all or every category) or for N top products
  having GROUPING_ID(ProductCategoryKey, flag_top_product, ProductKey) in (7, 3) or max(flag_top_product) = 'Y'
)
select 
	case
		when AggLevel = 7 then 'ALL PRODUCTS'
		when AggLevel = 3 then '  All ' || CategoryName
		when AggLevel = 1 then '    Top ' || @TopProductCount || ' ' || CategoryName
		when AggLevel = 0 then '      ' || Product
	end as DataSlice,
	TotalSalesAmount,
	[1] as TOP_1_State,
	[2] as TOP_2_State,
	[3] as TOP_3_State,
	[4] as TOP_4_State,
	[5] as TOP_5_State
from 
(
	select 
	AggLevel,
	CategoryName,
	Product,
	StateProvinceName,
	TotalSalesAmount,
	rn,
	-- total amount for every category (NULL as level 7)
	max(case when AggLevel in (7, 3) then TotalSalesAmount end) over(partition by CategoryName) TotalCategoryAmount
	from agg_orders_ext
	where 
	rn <= 5
) src
pivot
(
	max(StateProvinceName)
	for rn in ([1], [2], [3], [4], [5])
) as trans_states
order by TotalCategoryAmount desc, AggLevel desc, TotalSalesAmount desc
;