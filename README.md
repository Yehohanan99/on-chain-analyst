# On-Chain Data Analyst Portfolio

**Oluwadunsin** · [Dune profile](https://dune.com/yehohanan)

I analyze token launches on bonding curves: how they perform, how wallets behave around them, how fast tokens turn over, and how to present it in dashboards a whole team can use. Everything below is written in **SQL on Dune**.

**Live dashboard:** https://dune.com/yehohanan/pumpfun-launch-analytics

## Summary of findings

- About 42,000 tokens launch on pump.fun each day, and only about 2.5% graduate to PumpSwap within 24 hours.
- More than half of graduating tokens reach PumpSwap within 60 seconds of their first trade.
- Early buying is concentrated: about 1% of early wallets account for 39% of early positions, and they sell within 5 minutes 92% of the time.
- Graduation is a spike, not a lasting market: fewer than half of graduated tokens are still trading three days later.

## Projects

| # | Project | What it answers | SQL |
|---|---------|-----------------|-----|
| 1 | Launch funnel and graduation | How many launches, how many graduate, how fast? | [01_launch_funnel.sql](01_launch_funnel.sql) |
| 2 | Launch wallet behavior | How do early, mid and late wallets differ, and how concentrated is early buying? | [02a](02a_entry_timing.sql), [02b](02b_early_entry_concentration.sql) |
| 3 | Token velocity and decay | How fast do tokens turn over, and how quickly does activity fade after graduation? | [03a](03a_curve_turnover.sql), [03b](03b_activity_decay.sql) |
| 4 | Analytics dashboard | One dashboard for a non-technical team: headline counters, charts and definitions | [04_headline_kpis.sql](04_headline_kpis.sql), [dashboard](https://dune.com/yehohanan/pumpfun-launch-analytics) |

All four projects use **pump.fun on Solana**, the largest public bonding-curve dataset on Dune. The methods apply to any bonding-curve launchpad.

## Project 1: Launch Funnel and Bonding-Curve Graduation

**Chain:** Solana (pump.fun)

### Questions

- How many tokens launch per day, and how many attract real participation (10+ unique traders)?
- What share of launches graduate from the bonding curve within 24 hours?
- How long does graduation take (measured in seconds, since many are near-instant), and how much net SOL sits on the curve when it happens?

### Method

1. Build every bonding-curve trade from `dex_solana.trades` (`project = 'pumpdotfun'`), identifying the token side versus wrapped SOL.
2. Define a launch as the first curve trade seen for a mint; keep a clean cohort (drop the first and last day of the window).
3. Define graduation as the first PumpSwap trade (`project = 'pumpswap'`) within 24 hours of launch.
4. Aggregate per launch day: launches, participation, graduation rate, median time to graduation (in seconds), median net SOL at graduation (a data-driven check on the curve threshold).

### Findings

Snapshot: launches on Sep 16 to 18, 2026, with 24 hours of follow-up each (Dune query run on Sep 20, 2026).

- **Launch volume is steady:** about 41,500 to 43,900 tokens launched per day, and roughly 24% to 26% of them attracted 10+ unique traders.
- **Graduation is rare and stable:** about 2.5% of launches (roughly 1,050 to 1,100 a day) graduated to PumpSwap within 24 hours, with almost no day-to-day change.
- **The curve threshold is consistent:** the median net SOL on the curve at graduation was 85.005 on every day, which supports the graduation logic.
- **Graduation is often near-instant:** 54% to 58% of graduating tokens reached PumpSwap within 60 seconds of their first curve trade. The median time to graduation fell from 23 seconds (Sep 16) to 20 seconds (Sep 17) to 2 seconds (Sep 18). Three days is too short to call that a trend, but it points to bundled or automated launches, which Project 2 examines from the wallet side.

### Limitations

- Graduation is inferred from the first PumpSwap trade, so it can lag the actual migration by minutes.
- Launches are identified from trades, not creation events, so a token that never traded is invisible.
- The window is short by design to keep the query cheap (three full launch days); change the interval in the SQL for longer trends.
- Trader counts include bot and multi-wallet activity, so "10+ traders" overstates human participation.

### Files

- [01_sanity_check.sql](01_sanity_check.sql): run first to confirm the SOL side of trades
- [01_launch_funnel.sql](01_launch_funnel.sql): the funnel query
- Dune query: https://dune.com/queries/8785319


## Project 2: Wallet Behavior Around Token Launches

**Chain:** Solana (pump.fun)

### Questions

- Do wallets that buy in the first minute behave differently from mid and late entrants (position size, how fast they sell)?
- How concentrated is early buying: how much of it comes from wallets that enter dozens of launches in the first 60 seconds?

### Method

1. Build one row per (launch, wallet) with first buy time, first sell time, and SOL bought and sold.
2. Group wallets into entry cohorts by seconds since launch: early (60s), mid (10 min), late.
3. Compare median position size, share who sold within 5 minutes, and median time to first sell.
4. Group wallets by how many launches they entered early (1 to 4, 5 to 19, 20 to 99, 100+) and compare their share of wallets, share of early positions, and exit speed.

### Findings

Snapshot: launches on Sep 16 to 18, 2026 (Dune query run on Sep 20, 2026). Each row is a wallet's position in one launch.

| Entry group | Positions | Distinct wallets | Median buy (SOL) | Sold within 5 min | Ever sold | Median seconds to first sell |
|---|---|---|---|---|---|---|
| Early (first 60s) | 1,468,606 | 186,870 | 0.173 | 87.9% | 94.0% | 15 |
| Mid (1 to 10 min) | 824,739 | 166,310 | 0.111 | 71.2% | 88.5% | 68 |
| Late (after 10 min) | 336,391 | 96,794 | 0.129 | 52.5% | 82.7% | 149 |

- **Most activity is in the first minute:** early entrants account for about 56% of all wallet positions, more than mid and late combined.
- **Early buyers exit the fastest:** 88% sold within 5 minutes, and the median first sale came 15 seconds after the first buy. Late entrants took about 10 times longer (149 seconds).
- **Early wallets are repeat participants:** on average an early wallet appears in about 8 launches, versus about 5 for mid and 3.5 for late. That fits automated or repeat-sniping behavior, though this query alone cannot prove it.
- **Position sizes are similar across groups** (median about 0.11 to 0.17 SOL), so the difference is timing and speed of exit, not size.

**How concentrated is early buying?** Wallets grouped by how many launches they entered in the first 60 seconds:

| Early entries per wallet | Wallets | Share of wallets | Share of early positions | Sold within 5 min |
|---|---|---|---|---|
| 1 to 4 launches | 145,173 | 77.7% | 17.5% | 77.6% |
| 5 to 19 launches | 30,595 | 16.4% | 17.4% | 85.9% |
| 20 to 99 launches | 9,293 | 5.0% | 26.1% | 90.4% |
| 100+ launches | 1,809 | 1.0% | 39.0% | 91.6% |

- **Early buying is highly concentrated:** about 1,800 wallets (1% of early wallets) account for 39% of all early positions, and wallets that enter 20+ launches (about 11,100 wallets, 6%) account for 65%.
- **The most frequent wallets also exit the fastest:** 92% of their early positions were sold within 5 minutes, versus 78% for occasional early buyers.
- **Reading:** a small group of high-frequency wallets dominates the first minute of launches and flips quickly, which is consistent with automated sniping. This is a behavioral pattern, not proof of intent, and no individual wallet is identified.

### Limitations

- Wallet is not person: one operator can run many wallets, and many early buyers are bots.
- "Frequent early entrant" is a behavior label, not proof of insider activity. No individual wallet is named or accused.
- Sales are counted only on the bonding curve, so sales after graduation to PumpSwap are not included and "ever sold" is understated for tokens that graduated.
- A wallet can appear in more than one entry group, so distinct-wallet counts are not additive.

### Files

- [02a_entry_timing.sql](02a_entry_timing.sql): https://dune.com/queries/8785386
- [02b_early_entry_concentration.sql](02b_early_entry_concentration.sql): https://dune.com/queries/8785479


## Project 3: Token Velocity and Activity Decay

**Chain:** Solana (pump.fun and PumpSwap)

### Definitions

- **Curve turnover** = gross SOL traded on the curve / peak SOL held on the curve. Higher means more churn per unit of capital.
- **Activity decay** = how volume, active traders and share of tokens still trading fall in the days after graduation.
- **Holding time** (from Project 2) = median seconds from first buy to first sell.

### Questions

- Do graduated tokens turn over their curve capital faster than tokens that stall?
- How quickly does trading fade after graduation?

### Method

1. Compute a running curve balance per launch and take its peak.
2. Divide gross buy + sell volume by that peak, and compare graduated versus non-graduated launches.
3. For graduated tokens, measure PumpSwap volume, active traders and share still trading for days 0 to 3, counting only fully observed days and treating quiet days as zero.

### Findings

Snapshot: launches on Sep 16 to 18, 2026 (Dune query run on Sep 20, 2026). Only launches that held at least 1 SOL on the curve are included.

**Curve turnover** (gross SOL traded / peak SOL held on the curve):

| Outcome | 25th percentile | Median | 75th percentile |
|---|---|---|---|
| Did not graduate | 2.07 | 2.71 | 4.31 |
| Graduated within 24h | 1.00 | 1.00 | 6.23 |

- **Non-graduated tokens churn more:** the median token that stalled saw about 2.7 times its peak curve balance traded, meaning buyers and sellers kept trading against each other.
- **The typical graduated token had almost no selling on the curve:** a median turnover of exactly 1.0 means total SOL traded equalled the peak balance, so the curve was filled by buys alone. This matches the near-instant graduations (Project 1) and the fast early buyers (Project 2).
- **A minority of graduated tokens were heavily traded:** the 75th percentile is 6.2, above the non-graduated group, so there appear to be two kinds of graduates: instant fills and longer, contested climbs.

**Activity after graduation** (tokens that graduated within 24h of launch, PumpSwap trading by days since first PumpSwap trade; only fully observed days are counted):

| Days after graduation | Graduated tokens observed | Share still trading | Median volume (USD) | Median active traders |
|---|---|---|---|---|
| 0 | 5,254 | 100% | 104,749 | 705 |
| 1 | 4,843 | 59.9% | 0.10 | 1 |
| 2 | 3,768 | 52.0% | 0.0004 | 1 |
| 3 | 2,690 | 47.4% | 0.000006 | 0 |

- **Activity collapses almost immediately.** On day 0 the median graduated token trades about $105k with 705 active traders. By day 1 the median token is essentially dormant (about $0.10 of volume, one trader).
- **Only 59.9% of graduated tokens see any trade on day 1, and fewer than half (47.4%) by day 3.** Graduation is a spike, not a lasting market, for the typical token.
- **This is a median view.** A minority of tokens keep trading, so the mean could look quite different; the median describes the typical graduate.

### Limitations

- Market cap is not available directly, so velocity is defined relative to curve capital, not market cap.
- Graduation is inferred from the first PumpSwap trade. PumpSwap pools can exist for tokens whose curve never filled, so some tokens counted as graduated here may not have completed the curve; this query's graduated-launch count is lower than Project 1's, which may reflect that.
- Days after graduation are limited by the query window; change the interval in the SQL for a longer decay curve.
- Trades without a USD price count as zero volume, which may understate late-day volume for very small pools.
- Day 0 begins at the first PumpSwap trade, so it includes the immediate post-migration burst.

### Files

- [03a_curve_turnover.sql](03a_curve_turnover.sql): https://dune.com/queries/8785505
- [03b_activity_decay.sql](03b_activity_decay.sql): https://dune.com/queries/8785542


## Project 4: Analytics Dashboard

**Live dashboard:** https://dune.com/yehohanan/pumpfun-launch-analytics

The dashboard combines headline counters, charts and a definitions box, so a non-technical reader can see the main numbers first and the detail behind them.

### What is on it

1. A definitions and limitations box (text)
2. Four headline counters: average launches per day, graduation rate (24h), share graduating within 60 seconds, and median seconds to graduate ([04_headline_kpis.sql](04_headline_kpis.sql))
3. Bar chart: graduation rate by launch day
4. Bar chart: share of positions sold within 5 minutes and ever, by entry timing
5. Bar chart: share of wallets versus share of early positions, by how often a wallet enters early
6. Bar chart: curve turnover by outcome (25th percentile, median, 75th percentile)
7. Line chart: share of graduated tokens still trading, by day after graduation

### Metric definitions

- **Launch:** first bonding-curve trade seen for a token.
- **Graduation (24h):** first PumpSwap trade within 24 hours of launch.
- **Early buyer:** wallet whose first buy is within 60 seconds of launch.
- **Curve turnover:** gross SOL traded / peak SOL held on the curve.

### Design choices

- Definitions are on the dashboard itself, so no metric appears without an explanation.
- Every query uses the same time window (5 days, or 7 for the post-graduation decay), so all tiles describe the same launches.
- Limitations are stated on the dashboard and in each project section.

### Known limits of the dashboard

- It is a snapshot of three launch days, not a live feed, and it has no scheduled refresh.
- Tiles are stacked in a single column, and some chart legends use raw column names.

## Data and method notes

- Source tables: `dex_solana.trades` (`project = 'pumpdotfun'` for curve trades, `'pumpswap'` for post-graduation trades).
- Graduation is inferred from the first PumpSwap trade, so it is a proxy, not an on-chain flag.
- Wallet analysis describes behavior. A wallet is not a person, and no wallet is accused of anything.
- Results are a snapshot from September 20, 2026. Rerunning a query later covers different launch days.

## Reproduce

1. Create a free account at [dune.com](https://dune.com).
2. Open a new query and paste the SQL from one of the files above.
3. Run it. Each query has its time window written in, so no parameters are needed.

## About me

I am an on-chain data analyst focused on token launches: how bonding curves perform, how wallets behave around them, and how to explain it in dashboards a whole team can use. I work mainly in SQL on Dune, and I am looking for remote analyst roles at launchpads and DeFi teams.
