-- Project 2B: How concentrated is early buying? Wallets grouped by how many launches they entered in the first 60 seconds
-- Engine: Dune SQL (Trino). Window: last 5 days (relative to today)
WITH curve AS (
    -- Every bonding-curve trade on pump.fun in the window (one row per trade)
    SELECT
        CASE WHEN token_bought_mint_address = 'So11111111111111111111111111111111111111112'
             THEN token_sold_mint_address
             ELSE token_bought_mint_address END          AS mint,
        block_time,
        trader_id,
        CASE WHEN token_sold_mint_address = 'So11111111111111111111111111111111111111112'
             THEN 'BUY' ELSE 'SELL' END                  AS side,
        CASE WHEN token_sold_mint_address = 'So11111111111111111111111111111111111111112'
             THEN token_sold_amount
             ELSE token_bought_amount END                AS sol_amount,
        amount_usd
    FROM dex_solana.trades
    WHERE project = 'pumpdotfun'
      AND block_date >= current_date - interval '5' day
),
launches AS (
    -- A launch = first bonding-curve trade seen for a mint
    SELECT
        mint,
        MIN(block_time)                                            AS launched_at,
        COUNT(*)                                                   AS trades,
        COUNT(DISTINCT trader_id)                                  AS traders,
        SUM(CASE WHEN side = 'BUY'  THEN sol_amount ELSE 0 END)    AS buy_sol,
        SUM(CASE WHEN side = 'SELL' THEN sol_amount ELSE 0 END)    AS sell_sol
    FROM curve
    GROUP BY 1
),
cohort AS (
    -- Drop the first day of the window (tokens launched earlier would look new)
    -- and any day without a full 24h of follow-up (too young to judge graduation)
    SELECT mint, launched_at, trades, traders, buy_sol, sell_sol
    FROM launches
    WHERE launched_at >= date_trunc('day', now()) - interval '5' day + interval '1' day
      AND launched_at <  date_trunc('day', now()) - interval '1' day
)
,
positions AS (
    -- One row per (launch, wallet): when they first bought / sold and how much
    SELECT
        t.mint,
        t.trader_id,
        MIN(CASE WHEN t.side = 'BUY'  THEN date_diff('second', c.launched_at, t.block_time) END) AS first_buy_s,
        MIN(CASE WHEN t.side = 'SELL' THEN date_diff('second', c.launched_at, t.block_time) END) AS first_sell_s,
        SUM(CASE WHEN t.side = 'BUY'  THEN t.sol_amount ELSE 0 END)                              AS buy_sol,
        SUM(CASE WHEN t.side = 'SELL' THEN t.sol_amount ELSE 0 END)                              AS sell_sol
    FROM curve t
    JOIN cohort c ON c.mint = t.mint
    GROUP BY 1, 2
),
buyers AS (
    SELECT
        mint,
        trader_id,
        first_buy_s,
        first_sell_s,
        buy_sol,
        sell_sol,
        CASE
            WHEN first_buy_s <=  60 THEN '1. Early (first 60 seconds)'
            WHEN first_buy_s <= 600 THEN '2. Mid (1 to 10 minutes)'
            ELSE                         '3. Late (after 10 minutes)'
        END AS entry_group,
        (first_sell_s IS NOT NULL AND first_sell_s >= first_buy_s) AS sold_ever,
        (first_sell_s IS NOT NULL AND first_sell_s >= first_buy_s
         AND first_sell_s - first_buy_s <= 300)                    AS sold_within_5m
    FROM positions
    WHERE first_buy_s IS NOT NULL
)
,
early AS (
    SELECT
        trader_id,
        COUNT(*)                                     AS launches_entered_early,
        COUNT(*) FILTER (WHERE sold_within_5m)       AS sold_5m_positions
    FROM buyers
    WHERE first_buy_s <= 60
    GROUP BY 1
)
SELECT
    CASE
        WHEN launches_entered_early >= 100 THEN '4. 100+ launches'
        WHEN launches_entered_early >=  20 THEN '3. 20 to 99 launches'
        WHEN launches_entered_early >=   5 THEN '2. 5 to 19 launches'
        ELSE                                    '1. 1 to 4 launches'
    END                                                                     AS early_entry_frequency,
    COUNT(*)                                                                AS wallets,
    SUM(launches_entered_early)                                             AS early_positions,
    COUNT(*) * 1.0 / SUM(COUNT(*)) OVER ()                                  AS share_of_wallets,
    SUM(launches_entered_early) * 1.0 / SUM(SUM(launches_entered_early)) OVER () AS share_of_early_positions,
    SUM(sold_5m_positions) * 1.0 / SUM(launches_entered_early)              AS share_sold_within_5m
FROM early
GROUP BY 1
ORDER BY 1
