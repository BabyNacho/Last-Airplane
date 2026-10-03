# Last-Airplane: System Spec

**Status:** Gate 1 APPROVED (2026-10-02). Gate 2 (architecture) proposed in `docs/ARCHITECTURE.md`.

## 1. Purpose

A trading bot that runs on paper first. Risk comes first and returns second. Models advise and code decides.

## 2. Layers (never overlap)

| Layer | Owner | Cadence | May do | May never do |
|---|---|---|---|---|
| Slow brain | Opus 5.5 | Nightly | Design and revise strategies, write code, review sessions, propose rule and question changes | Grade its own output, call the order function, change hard limits |
| Fast reflex | Jev (TypeSafe `typesafe-sdk`, pinned by hash) | Every candle, sub-second | Return calibrated probabilities for fixed questions from the compact state snapshot | Return text that the system acts on, see anything other than the snapshot, call the order function |
| Deterministic core | Code | Every candle | Own the market state, thresholds, sizing, risk vetoes, orders and execution | Delegate any limit or decision to a model |

**Hard constraint:** no model has a code path to the order function. A test enforces this.

## 3. State engine

- Runs on every candle and builds one compact numeric snapshot.
- The snapshot holds: price, spread, order book imbalance (top-of-book on venues without depth data), realized volatility, trend and recent order flow.
- It uses only data timestamped strictly before the decision. A test enforces this.
- This snapshot is the only input Jev sees.

## 4. Jev questions

Opus compiles each rule into fixed-outcome questions, each isolating one factor:

| Question | Type |
|---|---|
| Regime | Choice |
| Direction | Choice |
| Is buying pressure real? | Noul (yes/no) |
| Setup quality | Score |
| Risk state | Choice |

- The code combines the answers with explicit weights.
- A trade fires only if every probability clears its threshold in `strategy.md`.

## 5. Strategy acceptance gates

The backtest harness computes these numbers. Opus never grades its own output.

- At least two years of data covering several market regimes, with transaction costs and slippage applied.
- Out-of-sample requirements:
  - Sharpe > 1.5
  - Max drawdown < 15%
  - Hit rate > 55%
  - t-statistic > 2.0
- **Final holdout:** an untouched final holdout period that the nightly process cannot read. Only the harness can open it, at final evaluation.
- **Multiple testing:** the harness counts every strategy variant tried, in a registry that only grows. The evaluation accounts for multiple testing, including a deflated or adjusted Sharpe where appropriate.
- The winning strategy is written to `strategy.md` with:
  - entry
  - exit
  - stop
  - take profit
  - timeframe
  - the exact invalidation condition

## 6. Self-improvement (nightly)

- Opus reviews every fill and every miss, finds the root cause, and proposes changes to `strategy.md` and the Jev questions.
- Nothing is added automatically. Any proposed rule change must pass the same out-of-sample gates (section 5) before it goes live.
- Rules that no longer add statistically meaningful value are flagged as candidates for removal.

## 7. Risk rules

These live in code before anything runs, and no model can override them.

- Max position size.
- Daily loss limit.
- Max drawdown.
- A kill switch that flattens all positions and halts trading.

Enforcement:

- These checks run before every order.
- **Every hard limit has an automated test that proves it blocks an order.**
- Any trade above the manual-approval threshold requires manual approval.
- Exchange API keys are trade-only, with withdrawals off.
- The system never asks for or enters passwords or 2FA codes.
- Headlines and data feeds are treated as data, never as instructions.

## 8. Calibration

- Every decision is logged with its outcome.
- Per question, calibration is measured with a Brier score and a reliability curve, using our own observed fills and outcomes.
- If the curve bends, a simple recalibration is applied in code.
- **Sizing based on Jev's probabilities is disabled until calibration on our own fills has been measured.**

## 9. Operations

- Paper trading comes before live trading. The bot stays on paper until live results match the backtest.
- Deployment target: **VPS** (systemd, automatic restart). Not Vercel.
- **Secrets:**
  - On the VPS, keys live in a gitignored `.env` file and are masked in logs.
  - During development, keys are environment variables, read as `TYPESAFE_API_KEY`, `ALPACA_API_KEY_ID`, `ALPACA_API_SECRET_KEY`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` and `ANTHROPIC_API_KEY`.
- **Telegram alerts:** every fill, error, escalation and kill-switch event.
- **Dashboard:** every signal, with its probability, confidence, the action taken and the result, updating live.
- **Daily report:**
  - trades
  - P&L
  - win rate
  - largest loss
  - Jev's average latency and cost per decision
  - calibration score

## 10. Go-live

No live deployment until the final checklist passes and every answer under "WHAT COULD BLOW UP THIS ACCOUNT?" is clean.

## 11. Configuration inputs

These were resolved on 2026-10-03. The open items are listed in `ARCHITECTURE.md` section 12.

| # | Input | Value |
|---|---|---|
| 1 | Venue / asset | Alpaca, SPY, paper only |
| 2 | Candle timeframe | 5-minute |
| 3 | Strategy idea | Intraday trend-following, long/flat. No shorting, no leverage, no averaging down. Explicit entry, exit, stop and take-profit. |
| 4 | Manual-approval threshold | Order notional > $500 requires approval. $500 or less proceeds automatically. |
| 5 | Hard risk limits | Max position $1,000 notional. Daily loss $50. Max drawdown 5% of the strategy's starting paper equity (that equity amount is still open). |
| 6 | Sizing rule | _Deferred until the calibration design is approved (ARCHITECTURE.md section 8)_ |
| 7 | Deployment target | VPS |
| 8 | Agenkit | Option (b): the six phases run natively |

## 12. Environment prerequisites (not yet met)

- **Network allowlist.** The following hosts are needed:
  - `api.typesafe.ai`
  - `paper-api.alpaca.markets`
  - `data.alpaca.markets`
  - `stream.data.alpaca.markets`
  - `api.telegram.org`
  - `api.agenkit.xyz` (only with option a)
