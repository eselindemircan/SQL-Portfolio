---------FACEBOOK-----------
select 
       ad_date, 
       campaign_id,
       adset_id,
       spend,
       impressions,
       reach,
       clicks,
       leads,
       value, 
       url_parameters,
       total
from public.facebook_ads_basic_daily;

--------GOOGLE-------------
select ad_date, 
       campaign_name,
       adset_name,
       spend,
       impressions,
       reach,
       clicks,
       leads,
       value, 
       url_parameters
from public.google_ads_basic_daily;

-------FBADSET-------------
select adset_id,
       adset_name
from public.facebook_adset;

--------FBCAMPAIGN---------
select campaign_id,
       campaign_name
from public.facebook_campaign;
 


----Google ve Facebook için günlük harcama metriklerinin ortalama, maksimum ve minimum değerlerini ayrı ayrı göster.
-----Toplam ROMI (Google ve Facebook dahil) açısından en yüksek 5 günü sırala (azalan şekilde tarih ve değer).
----Haftalık en yüksek toplam value’ya sahip kampanyayı bul (haftayı ve rekor değerini belirt).
-------Aylık bazda en büyük erişim artışı yaşayan kampanyayı belirle.
--------En uzun kesintisiz gösterime sahip adset_name’i (Google + Facebook) ve süresini gösteren sorguyu yaz.


----Google ve Facebook için günlük harcama metriklerinin ortalama, maksimum ve minimum değerlerini ayrı ayrı göster.
with combined_data as (select fb.spend as facebook_spend ,g.spend as google_spend
from public.facebook_ads_basic_daily fb
join public.google_ads_basic_daily g on fb.ad_date=g.ad_date 
)
select round(avg(facebook_spend)) as avg_fb_spend, round(avg(google_spend)) as avg_google_spend, 
       max(facebook_spend) as max_fb_spend,max(google_spend) as max_google_spend,
       min(facebook_spend) as min_fb_spend,min(google_spend) as min_google_spend
from combined_data

-----Toplam ROMI (Google ve Facebook dahil) açısından en yüksek 5 günü sırala (azalan şekilde tarih ve değer).
with combined_data as (
  select 
    fb.ad_date,
    coalesce(fb.value, 0) as facebook_value, 
    coalesce(g.value, 0) as google_value, 
    coalesce(fb.spend, 0) as facebook_spend,
    coalesce(g.spend, 0) as google_spend
  from public.facebook_ads_basic_daily fb
  join public.google_ads_basic_daily g on fb.ad_date = g.ad_date
)
select 
  ad_date,
  round(
    ((sum(facebook_value + google_value) - sum(facebook_spend + google_spend))::numeric
    / nullif(sum(facebook_spend + google_spend), 0) * 100), 2
  ) as total_romi
from combined_data
group by ad_date
order by total_romi desc nulls last
limit 5;

----Haftalık en yüksek toplam value’ya sahip kampanyayı bul (haftayı ve rekor değerini belirt).
with combined_data as (
  select
    fb.ad_date,
    campaign_name,
    coalesce(fb.value, 0) as facebook_value,
    coalesce(g.value, 0) as google_value
  from public.facebook_ads_basic_daily fb
  join public.google_ads_basic_daily g on fb.ad_date = g.ad_date
)
select 
  to_char(ad_date, 'WW') as week_number,
  campaign_name,
  sum(facebook_value + google_value) as total_value
from combined_data
group by week_number,campaign_name
order by total_value desc
limit 1;

-------Aylık bazda en büyük erişim artışı yaşayan kampanyayı belirle.
with monthly as (
  select
    date_trunc('month', fb.ad_date) as month,
    campaign_name,
    sum(coalesce(fb.reach, 0)) as fb_reach,
    sum(coalesce(g.reach, 0)) as g_reach
  from public.facebook_ads_basic_daily fb
  join public.google_ads_basic_daily g on fb.ad_date = g.ad_date
  group by month, campaign_name
),
growth as (
  select
    month,
    campaign_name,
    fb_reach - LAG(fb_reach) OVER (PARTITION BY campaign_name ORDER BY month) as fb_growth,
    g_reach - LAG(g_reach) OVER (PARTITION BY campaign_name ORDER BY month) as g_growth
  from monthly
),
max_growth as (
  select
    month,
    campaign_name,
    greatest(fb_growth, g_growth) as max_growth
  from growth
  where fb_growth is not null and g_growth is not null
)
select to_char(month,'MONTHYYYY')as month_of_growth,campaign_name, max_growth
from max_growth
order by max_growth desc
limit 1;

--------En uzun kesintisiz gösterime sahip adset_name’i (Google + Facebook) ve süresini gösteren sorguyu yaz.
-----------------------**********
with combined_adset as (
  select distinct ad_date, adset_name
  from (
    select ad_date, adset_name
    from public.facebook_ads_basic_daily fb
    join public.facebook_adset fa on fb.adset_id = fa.adset_id

    union all

    select ad_date, adset_name
    from public.google_ads_basic_daily
  ) combined
),
ranked as (
  select
    adset_name,
    ad_date,
    row_number() over (partition by adset_name order by ad_date) as rn
  from combined_adset
)
,
groups as (
  select
    adset_name,
    ad_date,
    ad_date - (rn || ' days')::interval as grp
  from ranked
),
streaks as (
  select
    adset_name,
    grp,
    count(*) as streak_days
  from groups
  group by adset_name, grp
)
select adset_name, streak_days
from streaks
order by streak_days desc
limit 1
