-- Project 3B: Activity decay after graduation (Solana, pump.fun -> PumpSwap)
-- Engine: Dune SQL (Trino). Window: last 7 days (relative to today)
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
      AND block_date >= current_date - interval '7' day
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
    WHERE launched_at >= date_trunc('day', now()) - interval '7' day + interval '1' day
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
      AND block_date >= current_date - interval '7' day
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
grads AS (
    SELECT s.mint, s.first_amm_trade_at
    FROM scored s
    WHERE s.graduated_24h
),
amm AS (
    SELECT
        CASE WHEN token_bought_mint_address = 'So11111111111111111111111111111111111111112'
             THEN token_sold_mint_address
             ELSE token_bought_mint_address END AS mint,
        block_time,
        trader_id,
        amount_usd
    FROM dex_solana.trades
    WHERE project = 'pumpswap'
      AND block_date >= current_date - interval '7' day
),
grid AS (
    -- every graduated token x every day index, but only days that are fully observed
    SELECT g.mint, g.first_amm_trade_at, d.day_idx
    FROM grads g
    CROSS JOIN UNNEST(sequence(0, 3)) AS d(day_idx)
    WHERE date_add('day', d.day_idx + 1, g.first_amm_trade_at) <= now()
),
daily AS (
    SELECT
        gr.mint,
        gr.day_idx,
        SUM(a.amount_usd)              AS volume_usd,
        COUNT(DISTINCT a.trader_id)    AS traders
    FROM grid gr
    JOIN amm a
      ON a.mint = gr.mint
     AND a.block_time >= date_add('day', gr.day_idx,     gr.first_amm_trade_at)
     AND a.block_time <  date_add('day', gr.day_idx + 1, gr.first_amm_trade_at)
    GROUP BY 1, 2
)
SELECT
    gr.day_idx                                                       AS days_after_graduation,
    COUNT(*)                                                         AS graduated_tokens,
    COUNT(d.mint) * 1.0 / COUNT(*)                                   AS share_still_trading,
    approx_percentile(COALESCE(d.volume_usd, 0), 0.5)                AS median_volume_usd,
    approx_percentile(COALESCE(d.traders, 0), 0.5)                   AS median_active_traders
FROM grid gr
LEFT JOIN daily d ON d.mint = gr.mint AND d.day_idx = gr.day_idx
GROUP BY 1
ORDER BY 1
