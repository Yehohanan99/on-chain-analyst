-- Project 3A: Bonding-curve turnover (velocity) by outcome (Solana, pump.fun)
-- Turnover = gross SOL traded / peak SOL held on the curve.
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
migrated AS (
    -- First PumpSwap trade per mint = proxy for graduation from the curve
    SELECT
        CASE WHEN token_bought_mint_address = 'So11111111111111111111111111111111111111112'
             THEN token_sold_mint_address
             ELSE token_bought_mint_address END          AS mint,
        MIN(block_time)                                  AS first_amm_trade_at
    FROM dex_solana.trades
    WHERE project = 'pumpswap'
      AND block_date >= current_date - interval '5' day
    GROUP BY 1
),
scored AS (
    SELECT
        c.mint,
        c.launched_at,
        c.trades,
        c.traders,
        c.buy_sol,
        c.sell_sol,
        m.first_amm_trade_at,
        (m.first_amm_trade_at IS NOT NULL
         AND m.first_amm_trade_at <= c.launched_at + interval '24' hour) AS graduated_24h,
        date_diff('second', c.launched_at, m.first_amm_trade_at)         AS seconds_to_amm,
        c.buy_sol - c.sell_sol                                           AS net_sol
    FROM cohort c
    LEFT JOIN migrated m ON m.mint = c.mint
),
running AS (
    SELECT
        t.mint,
        SUM(CASE WHEN t.side = 'BUY' THEN t.sol_amount ELSE -t.sol_amount END)
            OVER (PARTITION BY t.mint ORDER BY t.block_time) AS curve_sol
    FROM curve t
    JOIN cohort c ON c.mint = t.mint
),
peak AS (
    SELECT mint, MAX(curve_sol) AS peak_curve_sol
    FROM running
    GROUP BY 1
),
turnover AS (
    SELECT
        s.mint,
        s.graduated_24h,
        (s.buy_sol + s.sell_sol) / p.peak_curve_sol AS turnover_ratio
    FROM scored s
    JOIN peak p ON p.mint = s.mint
    WHERE p.peak_curve_sol >= 1          -- ignore launches that never held 1 SOL
)
SELECT
    CASE WHEN graduated_24h THEN 'Graduated within 24h' ELSE 'Did not graduate' END AS outcome,
    COUNT(*)                                        AS launches,
    approx_percentile(turnover_ratio, 0.25)         AS p25_turnover,
    approx_percentile(turnover_ratio, 0.50)         AS median_turnover,
    approx_percentile(turnover_ratio, 0.75)         AS p75_turnover
FROM turnover
GROUP BY 1
ORDER BY 1
