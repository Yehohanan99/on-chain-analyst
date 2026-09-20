-- Project 4: Headline KPIs for the dashboard counters (Solana, pump.fun)
-- Engine: Dune SQL (Trino). Window: last 5 days (relative to today)
WITH curve AS (
    SELECT
        CASE WHEN token_bought_mint_address = 'So11111111111111111111111111111111111111112'
             THEN token_sold_mint_address
             ELSE token_bought_mint_address END AS mint,
        block_time,
        trader_id,
        CASE WHEN token_sold_mint_address = 'So11111111111111111111111111111111111111112'
             THEN 'BUY' ELSE 'SELL' END AS side,
        CASE WHEN token_sold_mint_address = 'So11111111111111111111111111111111111111112'
             THEN token_sold_amount
             ELSE token_bought_amount END AS sol_amount,
        amount_usd
    FROM dex_solana.trades
    WHERE project = 'pumpdotfun'
      AND block_date >= current_date - interval '5' day
),
launches AS (
    SELECT
        mint,
        MIN(block_time) AS launched_at,
        COUNT(*) AS trades,
        COUNT(DISTINCT trader_id) AS traders,
        SUM(CASE WHEN side = 'BUY' THEN sol_amount ELSE 0 END) AS buy_sol,
        SUM(CASE WHEN side = 'SELL' THEN sol_amount ELSE 0 END) AS sell_sol
    FROM curve
    GROUP BY 1
),
cohort AS (
    SELECT mint, launched_at, trades, traders, buy_sol, sell_sol
    FROM launches
    WHERE launched_at >= date_trunc('day', now()) - interval '5' day + interval '1' day
      AND launched_at <  date_trunc('day', now()) - interval '1' day
),
migrated AS (
    SELECT
        CASE WHEN token_bought_mint_address = 'So11111111111111111111111111111111111111112'
             THEN token_sold_mint_address
             ELSE token_bought_mint_address END AS mint,
        MIN(block_time) AS first_amm_trade_at
    FROM dex_solana.trades
    WHERE project = 'pumpswap'
      AND block_date >= current_date - interval '5' day
    GROUP BY 1
),
scored AS (
    SELECT
        c.mint,
        c.launched_at,
        (m.first_amm_trade_at IS NOT NULL
         AND m.first_amm_trade_at <= c.launched_at + interval '24' hour) AS graduated_24h,
        date_diff('second', c.launched_at, m.first_amm_trade_at) AS seconds_to_amm
    FROM cohort c
    LEFT JOIN migrated m ON m.mint = c.mint
)
SELECT
    COUNT(*) * 1.0 / COUNT(DISTINCT CAST(date_trunc('day', launched_at) AS date)) AS avg_launches_per_day,
    100.0 * COUNT(*) FILTER (WHERE graduated_24h) / COUNT(*) AS graduation_rate_pct,
    100.0 * COUNT(*) FILTER (WHERE graduated_24h AND seconds_to_amm < 60)
        / NULLIF(COUNT(*) FILTER (WHERE graduated_24h), 0) AS graduated_under_60s_pct,
    approx_percentile(seconds_to_amm, 0.5) FILTER (WHERE graduated_24h) AS median_seconds_to_graduation
FROM scored
