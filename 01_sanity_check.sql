-- Run this first. One side of nearly every row should be SOL / WSOL.
-- If it is not, the mint-detection logic in the other queries needs adjusting.
SELECT
    project,
    token_bought_symbol,
    token_sold_symbol,
    COUNT(*) AS trades
FROM dex_solana.trades
WHERE project IN ('pumpdotfun', 'pumpswap')
  AND block_date >= current_date - interval '1' day
GROUP BY 1, 2, 3
ORDER BY 4 DESC
LIMIT 20
