# Last-Airplane: Gate 2 Architecture and Calibration Design

**Status:** PROPOSED. Awaiting approval. No code until approved.
**Inputs:** `docs/SPEC.md` (Gate 1, approved) plus the configuration below.

| Config | Value |
|---|---|
| Venue / asset | Alpaca, SPY, **paper only** |
| Timeframe | 5-minute candles, regular trading hours (RTH) only |
| Strategy family | Intraday trend-following. Long or flat only, with no shorting, no leverage and no averaging down. |
| Manual approval | Order notional **> $500** needs approval. Exactly $500 or less proceeds automatically. |
| Max position | $1,000 notional |
| Daily loss limit | $50 |
| Max drawdown | 5% of the strategy's starting paper equity (**amount still open, see section 12**) |
| Agenkit | Option (b): the six phases run natively |
| Deploy | VPS |

---

## 1. Process topology

Four processes run on the VPS. Each runs under its own Unix user and holds its own set of credentials.

```
 ┌────────────────────────── VPS ──────────────────────────────────────────┐
 │                                                                         │
 │  [trader]  user: trader      creds: ALPACA_*, TYPESAFE_API_KEY, TG_*    │
 │    MarketData → StateEngine → Strategy → Reflex(Jev) → Sizing           │
 │      → RiskGate → ApprovalGate → OrderRouter ──► Alpaca paper           │
 │    Ledger / EventLog (SQLite, append-only) ◄── fills, reconciliation    │
 │                                                                         │
 │  [watchdog] user: watchdog   creds: ALPACA_* (separate key)             │
 │    heartbeat check, flatten-on-silence, independent kill switch         │
 │                                                                         │
 │  [brain]   user: brain       creds: ANTHROPIC_API_KEY ONLY              │
 │    nightly Opus: review → proposal (strategy.md / questions.yaml diff)  │
 │    NO Alpaca keys, NO network route to Alpaca, NO holdout read access   │
 │                                                                         │
 │  [harness] user: harness     creds: none (reads data, runs backtests)   │
 │    backtest, trial registry, gates, holdout vault (sole reader)         │
 │                                                                         │
 │  [dashboard] read-only view of EventLog, bound to 127.0.0.1             │
 └─────────────────────────────────────────────────────────────────────────┘
```

**How "models can never call the order function" is enforced.** There are three independent layers:

1. **Credential separation.** The `brain` process has no Alpaca key, and an egress firewall rule for the `brain` user drops traffic to Alpaca hosts.
2. **Import boundary.** Only `execution/` may import the Alpaca trading client. An `import-linter` contract fails CI otherwise, so `reflex/` and `brain/` cannot import `execution/`, `risk/` or `sizing/`.
3. **Data typing.** Jev returns probabilities, and they reach the decision path only as `float`s inside a frozen dataclass. No model output is ever executed, evaluated or used as a function or field name.

## 2. Module layout

```
src/lastairplane/
  config/       limits.py (hard limits, constants in code, not YAML), loader for strategy.md
  data/         Alpaca bars/quotes/trades ingest, bar store, market calendar, macro calendar
  state/        snapshot builder: PURE function (bars_before_t) -> Snapshot
  strategy/     deterministic signal rules: PURE function (Snapshot, params) -> Signal
  reflex/       Jev client, questions.yaml, recalibrators, fail-closed wrapper
  sizing/       sizing policy (selected after calibration; see section 8)
  risk/         RiskGate, KillSwitch, persistent HALT flag
  approval/     manual-approval queue (Telegram inline buttons, default-deny on timeout)
  execution/    OrderRouter: the ONLY module that can place or cancel orders
  ledger/       event log, positions, P&L, broker reconciliation
  backtest/     event-driven simulator, cost model, metrics, DSR, trial registry, holdout vault
  calibration/  outcome labelling, Brier/RPS, reliability curves, drift monitor
  brain/        nightly Opus orchestration (proposals only)
  alerts/       Telegram notifier (outbound only, except approve/deny/kill)
  dashboard/    FastAPI + server-sent events, read-only
  reports/      daily report
```

The same `state/`, `strategy/`, `sizing/` and `risk/` code runs in both the backtest and live trading. The backtest swaps only `data/` (historical) and `execution/` (simulated fills). This shared code is what keeps backtest and live results comparable.

## 3. Data and the lookahead firewall

- **Source:** Alpaca Market Data v2 for SPY: 5-minute bars, quotes (NBBO) and trades.
  - The free plan streams IEX-only data in real time.
  - Historical SIP data is available beyond a 15-minute delay.
  - The backtest uses SIP history. **Known gap:** live order-flow features computed from IEX are noisier than the same features computed from SIP. The build will measure feature drift between the two feeds, or you can upgrade the data plan. *(Must be verified against current Alpaca plan terms once the network is allowlisted.)*
- **Timestamp convention:** Alpaca bar timestamps mark the bar **start**. The bar stamped 10:00 covers 10:00:00 to 10:04:59 and becomes *knowable* at 10:05:00. The store keeps `available_at = start + 5min` on every row. Every read takes the form `bars where available_at <= decision_time`.
- **Decision and fill timing:**
  - A decision is made at `t` (the bar close) using data with `available_at <= t`.
  - In the backtest, the simulated fill is at the **next bar's open plus the cost model**, never at the close of the bar that triggered it.
- **Lookahead test (written first):** a property-based test mutates every bar with `available_at > t`, rebuilds the snapshot at `t`, and asserts that it is byte-identical. The test runs against every feature.
- **Session rules:**
  - RTH only.
  - No entries before 09:45 ET (the opening auction leaves noisy data) or after 15:30 ET.
  - All positions are flattened at 15:50 ET (half days: 12:50 ET). Nothing is held overnight.
  - The calendar comes from Alpaca's calendar API.
  - A **macro blackout** file (FOMC, CPI, NFP) is a version-controlled list of timestamps, treated as data, that blocks entries from N minutes before to M minutes after each event. N and M are strategy parameters.

## 4. State snapshot (the only thing Jev sees)

The snapshot is numeric and normalized. It contains **no ticker, date or wall-clock time**, which limits how much Jev can recognize the period it is looking at (see section 7.6).

| Field | Definition |
|---|---|
| `ret_1`, `ret_6`, `ret_12` | Log returns over 1, 6 and 12 bars, divided by ATR% |
| `spread_bps` | Time-weighted mean quoted spread over the last bar, in bps |
| `tob_imbalance` | (bid_size − ask_size) / (bid_size + ask_size), time-weighted over the last bar. **Top of book only**, because Alpaca equities have no depth data. |
| `rv_12`, `rv_pct` | Realized volatility over 12 bars, and its percentile vs the trailing 20 sessions |
| `trend_slope`, `trend_r2` | OLS slope (ATR units) and R² of the last N closes |
| `ema_gap` | (EMA_fast − EMA_slow) / ATR |
| `vwap_gap` | (close − session VWAP) / ATR |
| `adx` | ADX(14) / 100 |
| `signed_vol_12` | Tick-rule signed volume over 12 bars / total volume |
| `session_phase` | Minutes since the open / 390, bucketed into 6 bins |
| `in_position` | 0 or 1 |

Every field is clipped to a fixed range and rounded to 4 decimal places. The snapshot schema is versioned, and a snapshot-schema change resets calibration history (section 7).

## 5. Strategy definition (the parameter space, declared before any backtest)

There are no arbitrary hard-coded values. The **search space is declared in advance** and frozen in `backtest/search_space.yaml`. Every point evaluated is recorded in the trial registry.

**Rule template (long or flat):**

- **ENTRY:** all of the following on the bar close at `t`:
  - `EMA(fast) > EMA(slow)`, the trend condition
  - `close > session VWAP`, the intraday trend confirmation
  - `ADX(14) >= adx_min`, a momentum or strength filter
  - `rv_pct <= vol_cap_pct`, to stay out of extreme-volatility regimes
  - the session-window and macro-blackout checks pass
  - not already in a position, and no entry within `cooldown` bars of the last exit
  - **the Jev gate passes**: each probability is above its threshold in strategy.md (section 6)
- **STOP:** entry − `k_stop` × ATR(14). It is fixed at entry and never widened.
- **TAKE PROFIT:** entry + `k_tp` × ATR(14).
- **EXIT:** whichever comes first:
  - the stop is hit
  - the take-profit is hit
  - `EMA(fast) < EMA(slow)` on the bar close
  - `close < VWAP` for 2 consecutive bars
  - the 15:50 ET flatten
- **INVALIDATION:** the setup is void if `EMA(fast) <= EMA(slow)` *or* `close <= VWAP` at the moment of the entry decision. A pending entry is cancelled if this becomes true before the fill.

**Search grid (deliberately small: 3·3·2·3·2·2 = 216 variants):**

| Param | Values |
|---|---|
| `fast / slow` | (8, 21), (13, 34), (21, 55) |
| `adx_min` | 15, 20, 25 |
| `vol_cap_pct` | 0.80, 0.95 |
| `k_stop` | 1.0, 1.5, 2.0 |
| `k_tp` | 2.0, 3.0 |
| `cooldown` | 1, 3 bars |

ATR(14), ADX(14) and the 15:50 flatten are fixed rather than searched, so they don't inflate the trial count.

**Two-stage acceptance:**

1. The **deterministic baseline (no Jev)** must clear every gate on its own.
2. The **Jev overlay** must then show *incremental* value: it has to improve out-of-sample Sharpe without breaking any other gate, and its trial count is added to the same registry. If Jev adds nothing, the system trades the baseline, and Jev stays logging-only for calibration.

**⚠ Gate tension you should know about now.** Trend-following with `k_tp/k_stop >= 1` structurally tends toward hit rates **below 50%**: it wins through payoff size, not frequency. The **hit rate > 55%** gate and the **Sharpe > 1.5 for long-only intraday SPY after costs** gate together form a high bar. A likely and legitimate outcome is that **no variant passes**. If that happens, the system will not trade, and I will report it rather than widen the search to force a pass. I am not changing your gates. I'm flagging this so a "no strategy found" result doesn't come as a surprise.

## 6. Jev reflex layer

Each candle, while the deterministic ENTRY rule (excluding the Jev gate) is true or a position is open, the system makes one `system_one` call carrying all five questions.

| Key | Type | Options or levels | Used how |
|---|---|---|---|
| `regime` | Choice | trend_up, trend_down, range, disorderly | P(trend_up) ≥ θ_regime |
| `direction` | Choice | up, flat, down over next H bars | P(up) ≥ θ_dir |
| `buy_pressure_real` | Noul | yes / no | P(yes) ≥ θ_bp |
| `setup_quality` | Score | poor < fair < good < excellent | P(good ∪ excellent) ≥ θ_q |
| `risk_state` | Choice | normal, elevated, extreme | P(extreme) ≤ θ_risk (veto) |

- **Firing rule:** **every** threshold must pass (AND).
- **Weighted score:** `S = Σ w_i · p_i` uses explicit weights from strategy.md. It is logged and shown on the dashboard. It **cannot cause a trade on its own**, because the firing rule is the AND above.
- **Jev can only veto.** It can block an entry that the deterministic rule wants, but it can never create one. **Exits never wait on Jev.**
- **Probabilities pass through the recalibrator** (section 7) before thresholds are applied. The raw and calibrated values are both logged.
- **Fail-closed behaviour:**
  - Timeout of 800 ms, one retry (only if time remains before the next bar), schema-validation failure, or an API error all mean **no new entry** on that bar.
  - Three consecutive failures send a Telegram alert.
  - Jev's outage never blocks exits or the kill switch.
- **What gets logged per call:**
  - request hash
  - snapshot
  - raw distributions
  - confidence
  - latency
  - token count and cost
  - SDK version and model ID
- **Question versioning:** `questions.yaml` carries a version per question. **Changing a question's wording or options starts a new calibration series for that question**, which feeds the rate limit in section 9.

## 7. Calibration design (for approval)

### 7.1 Ground-truth labels (fixed and deterministic, defined before data is collected)

Each question needs a label that the code can compute after the fact. H is the strategy's holding horizon in bars, fixed by the winning strategy.

| Question | Label at decision time `t`, resolved at `t + H` |
|---|---|
| `direction` | Forward log return r over H bars: `up` if r > +0.25·ATR%, `down` if r < −0.25·ATR%, otherwise `flat` |
| `buy_pressure_real` | **yes** if price touches entry + 0.5·ATR before entry − 0.5·ATR within H bars (first passage); **no** otherwise, including if neither is touched |
| `setup_quality` | The R-multiple of the hypothetical trade under the live stop and take-profit rules, bucketed: < −0.5R poor, [−0.5, 0.5) fair, [0.5, 1.5) good, ≥ 1.5R excellent |
| `regime` | Over the next 12 bars: efficiency ratio ER = abs(net move) / sum(abs(moves)). If ER ≥ 0.5: trend_up when the net move > 0, otherwise trend_down. If ER < 0.5 and rv_pct ≥ 0.9: disorderly. Otherwise: range. |
| `risk_state` | Forward 12-bar realized volatility vs the trailing 20-session distribution: < p70 normal, p70 to p95 elevated, ≥ p95 extreme |

The constants (0.25, 0.5, 12, p70/p95) are **frozen as part of approving this design**. Changing them later starts a new calibration series.

### 7.2 Two populations, measured separately

- **A. All queried candles.** These are large in number and free of selection bias, and show whether Jev is calibrated at all on this venue's data.
- **B. Own fills.** These are only the candles where an order actually filled, with labels computed from **our actual fill price**. This is the population the spec requires before any probability-based sizing. It is smaller and affected by selection, and it is what matters for sizing.

**Caveat:** Alpaca *paper* fills don't model slippage, queue position or market impact. For a ≤ $1,000 SPY order the impact is small, but population B on paper is still optimistic, and it is re-measured on live fills before live sizing.

### 7.3 Metrics (per question, per population, with a rolling window and cumulative totals)

- **Brier score.** Multiclass Brier for Choice questions, binary for Noul, and the **ranked probability score (RPS)** for Score, because Score's levels are ordinal.
- **Brier skill score vs climatology**, meaning the base rate of each outcome in a trailing window. A calibrated forecaster that only predicts base rates is useless, so **BSS > 0** is required for a question to count as informative.
- **Murphy decomposition** into reliability, resolution and uncertainty, which separates "miscalibrated" from "uninformative".
- **Reliability curve.** There are 10 bins of equal sample count, built per class for Choice questions, with Wilson 95% intervals. These intervals are what show whether the curve bends.
- **ECE** (expected calibration error), with a bootstrap 95% confidence interval.
- **Log loss**, as a secondary metric.

### 7.4 Minimum sample sizes (proposed; set by this approval)

- **"Calibration measured" (population A):** ≥ 500 resolved labels per question **and** ≥ 30 per populated bin.
- **"Calibration verified on own fills" (population B):** ≥ 200 resolved fills **and** a Wilson interval of ≤ ±10 percentage points on the reliability of the decision-relevant bin.
- **Timing:** at about 0–3 trades a day, population B takes **months** to fill. Probability-based sizing stays **disabled** until then. This timeline follows directly from the spec's rule that calibration must be measured on our own fills.

### 7.5 Recalibration (in code; never fit and evaluated on the same data)

- **Method:**
  - Binary questions use Platt scaling (logistic regression on logit(p)).
  - Choice and Score questions use temperature scaling, with vector scaling if n > 2,000.
  - Isotonic regression is used only when n > 2,000 per question.
- **Time-ordered split.** The recalibrator is fit on the older 70% of the data and evaluated on the newer 30%.
- **Ships only if** it improves out-of-sample Brier by a margin that is significant under a paired bootstrap. Otherwise the identity mapping stays.
- **Versioning.** Recalibrators are versioned artifacts. Rollback means repinning the previous version.

### 7.6 Drift and leakage controls

- **Drift monitor.** A rolling 200-label Brier per question uses CUSUM against the deployed baseline. A breach triggers an alert, and **that question is set to veto-all** (fail-closed) until the recalibrator is refit and passes. Drift can make the system trade less, never more.
- **Leakage risk.** Jev may have been trained on data that covers the backtest period. Anonymized snapshots reduce this risk but can't eliminate it. Jev's measured value-add is therefore **trusted only on forward data**: paper trading after its model version date. The backtest overlay result (section 5, stage 2) is advisory, and forward results decide.

## 8. Sizing: options presented for your decision (none selected yet)

Every option sits underneath the hard caps in section 10. Sizing can only reduce exposure, never raise a cap.

| Option | Rule | Uses Jev? | When it's eligible |
|---|---|---|---|
| **S0 Fixed notional** | qty = floor_to_increment(N / ask) for a fixed N ≤ $500 | No | Immediately |
| **S1 Fixed-risk** | qty = risk_per_trade / (k_stop × ATR), capped at $1,000 notional, with risk_per_trade a fixed $ amount | No | Immediately |
| **S2 Capped fractional Kelly** | f = λ·(p·b − (1−p))/b using the **calibrated** p from population B and the backtest payoff ratio b, with λ ≤ 0.25, applied *on top of* S1 as a multiplier in [0, 1] | Yes | Only after section 7.4 population B is verified |

**My recommendation is S1 for paper**, because it ties the loss to the stop distance, which works naturally with a $50 daily limit. S2 should only be enabled later, as a downward-only multiplier, once calibration on our own fills is verified. You choose N or risk_per_trade.

## 9. Backtest harness, holdout and multiple testing

- **Data window:** SIP 5-minute history from 2018-01 onward. It covers the Q4-2018 selloff, the 2020 crash, the 2022 bear market and the 2023–25 rallies.

**Data splits:**

| Split | Period | Who can read it |
|---|---|---|
| Development | 2018-01 → 2023-12 | brain + harness |
| Validation (walk-forward OOS) | 2024-01 → 2024-12 | Metrics only, via the harness |
| **Final holdout** | **2025-01 → 2026-06** | **harness `final_eval` only** |

**Holdout vault:**

- The holdout data sits in a directory owned by the `harness` user with mode `0700`. The `brain` user cannot read it.
- `final_eval` writes a hash-chained entry to `holdout_access.log` on every open. Once opened, the holdout is **burned for that candidate family**, and from then on forward paper trading serves as the holdout.

**Development and out-of-sample walk-forward:**

- Rolling folds: 3-year train, 6-month test, rolling forward 6 months.
- Gates are computed on the concatenated test folds and the validation year.

**Cost model (applied to every fill):**

- Half the quoted spread at the decision bar.
- Slippage of max(1 bp, 0.1 × ATR% of 1-minute bars).
- SEC and FINRA TAF fees on sells.
- Alpaca equity commissions are $0, but the model has a `commission_per_share` parameter in case that changes.
- These are explicit parameters in `backtest/costs.yaml`. A stress test at 2× cost must not flip the sign of returns.

**Trial registry:**

- Append-only and hash-chained. It records every variant ever evaluated on development or validation data, from both the grid and the nightly proposals.
- `N_trials` is never reset.

**Gates (all must pass):**

- Out-of-sample Sharpe > 1.5 (annualized from daily P&L)
- Max drawdown < 15%
- Hit rate > 55%
- Newey–West t-stat > 2.0
- **Deflated Sharpe Ratio ≥ 0.95**, using N_trials, the variance of the Sharpe ratios across trials, and the skew and kurtosis of returns

**Gate evaluation:**

- The harness computes every metric. Opus receives the numbers as read-only results, never as a grading task.
- **Capital basis for gate metrics:** returns are computed on the strategy's allocated equity (section 12), so drawdown % and Sharpe mean the same thing in the backtest and live.

## 10. Risk gate (deterministic, before every order)

Order of checks inside `RiskGate.check(order, ledger, broker_state) -> Approve | Reject(reason) | NeedsApproval`:

1. **HALT flag present → Reject.** The flag is persistent on disk and survives restarts. It can be cleared only by a CLI command on the VPS, never by Telegram, the dashboard or a model.
2. **Order side and type.** Reject anything other than a long entry or a reduce-only exit, and reject shorts (`qty_after < 0`).
3. **Max position.** `position_notional + open_order_notional + order_qty × worst_price > $1,000` → Reject. Here worst_price = limit price, or ask × (1 + 0.5%) for market orders.
4. **Daily loss.** `realized_today + unrealized_now <= −$50` → Reject all entries, and the kill switch fires. A **pre-trade check** also rejects any entry whose loss at the stop, added to today's P&L, would exceed −$50.
5. **Max drawdown.** Strategy equity has drawn down ≥ 5% (see section 12 for the basis) → Reject, and the kill switch fires.
6. **No averaging down.** An entry while a position is already open → Reject.
7. **Data staleness.** The last bar is older than 2 bar intervals, or the quote is older than 10 s → Reject entries.
8. **Reconciliation.** The ledger position doesn't match the broker position → Reject, and the kill switch fires.
9. **Approval threshold.** `order_notional > $500` → NeedsApproval. Exactly $500.00 is allowed automatically.

**Exits** (stop, take-profit, flatten) are reduce-only and are **always allowed**, including under HALT and stale data, because nothing may ever block a flatten. Every check above applies only to orders that increase exposure.

- **Hard limits are Python constants** in `config/limits.py`. They are loaded nowhere else and have no override parameter. A test asserts that `strategy.md` and `questions.yaml` can't name any limit field.

**Kill switch:**

- **Triggers:**
  - the daily-loss limit
  - the max-drawdown limit
  - a reconciliation mismatch
  - 5 errors within 10 minutes
  - a manual trigger from the CLI, or `/kill` sent from the authorized Telegram chat ID
  - the watchdog detecting a missing heartbeat for more than 90 s during RTH
- **Action:**
  1. Cancel all open orders.
  2. Market-flatten the SPY position.
  3. Write the HALT flag.
  4. Send a Telegram alert.
  5. Verify that the broker position is 0, and retry with backoff if it isn't. If it still isn't 0, escalate the alert every minute.

**Manual approval:**

- A Telegram message with Approve and Deny buttons, accepted only from the authorized chat ID.
- **Default-deny after 60 s.**
- After approval, the order is **re-checked** through the full RiskGate at send time, because prices move.

## 11. Execution

- **Order types:** entry is a marketable limit order (ask + 0.02%, `day`, cancelled after 1 bar if unfilled). Exits are market orders.
- **⚠ Fractional-share constraint.** SPY trades well above $500 per share, so any whole-share order exceeds the $500 approval threshold, and **every** entry would need manual approval. The alternatives are:
  - **(F1)** Fractional orders (≤ $500, automatic). Alpaca doesn't support bracket or OCO orders on fractional quantities *(to be re-verified in build)*, so the **stop and take-profit are managed by code** on every quote tick. A bot crash then means no live stop at the broker. The independent **watchdog** process flattens any position whose owning heartbeat is silent for more than 90 s.
  - **(F2)** Whole shares with broker-side bracket orders, so the stop lives at the broker, but every entry needs manual approval.
  - **Recommendation: F1 for paper**, with the watchdog. This is a decision for you (section 12).
- **Idempotency.** Every order carries a `client_order_id` = hash(strategy version, bar time, intent). Retries can never double-submit.
- **Reconciliation:**
  - On startup, positions and open orders are pulled from the broker and compared to the ledger. Any mismatch means HALT.
  - The same check repeats every 60 s.
- **Pattern-day-trader (PDT) rule.** Intraday round trips are day trades. Paper accounts above $25k aren't affected. **For any future live account with less than $25k, PDT is a hard blocker**, and the final checklist covers it.

## 12. Decisions still needed from you (before Gate 3)

1. **Strategy starting equity.** What starting equity does the 5% max drawdown apply to? The Alpaca paper default account is $100k, which gives a limit of $5,000 that a $1,000 position cap can't realistically reach. I need the **allocated strategy equity**, for example $1,000 or $2,000.
2. **Drawdown basis.** Should drawdown be measured peak-to-trough on strategy equity, or as a loss from the starting equity? The text "5% of starting equity" supports either reading. I recommend peak-to-trough, with the limit amount fixed at 5% of starting equity.
3. **Fractional shares:** F1 (automatic, code-managed stops plus watchdog) or F2 (whole share, broker stops, manual approval on every entry)?
4. **Sizing:** S0, S1 or S2 (section 8), plus its $ parameter.
5. **Calibration constants and minimum sample sizes** in sections 7.1 and 7.4. Are they approved as written?
6. **Search grid** in section 5. Is it approved as written?

## 13. Nightly self-improvement loop

**Timing:** 17:00 ET, triggered by a systemd timer, running as the `brain` user.

**Steps:**

1. The harness exports a **sanitized session bundle**: the fills, the decisions, Jev distributions plus labels, and the risk rejections. Headlines and feeds are never included. The bundle content is labeled **as data** in the prompt.
2. Opus writes a root-cause review to `reviews/YYYY-MM-DD.md`, plus at most one **proposal**: a diff to `strategy.md` parameters or a `questions.yaml` change. Both are schema-validated, and limits are excluded by the schema.
3. The harness backtests the proposal on development and validation data, registers it as a trial, and computes all the gates plus DSR. The holdout is never touched.
4. **If the proposal passes:** it runs in **shadow mode** for 5 sessions. In shadow mode it logs decisions without orders, side by side with the live configuration. If shadow results stay consistent (within the backtest's 95% range), the proposal is promoted by repinning the config version, and rollback means repinning the previous version.
5. **Any change to Python code** proposed by Opus is opened as a branch or PR and **always requires your merge**. It never auto-promotes.

**Rule pruning:**

- Each month, the harness runs ablations, with each rule removed in turn.
- A rule whose removal doesn't degrade out-of-sample DSR or Sharpe by a statistically meaningful margin (paired bootstrap, p > 0.1) is flagged for removal. Removals go through the same gates.

**Question-change rate limit:** at most one `questions.yaml` change per question per 20 sessions. Otherwise calibration population B never reaches its minimum size.

## 14. Observability

- **Dashboard.** FastAPI with server-sent events on `127.0.0.1:8080`, accessed over an SSH tunnel or Tailscale, so it is never exposed publicly.
  - It is read-only, with no trading controls.
  - **Panels:**
    - a live signal table: time, signal, every question's raw and calibrated probability, confidence, S, the action and the reject reason, and the result
    - positions
    - P&L
    - risk headroom
    - reliability curves
    - Jev latency
- **Telegram alerts:**
  - fills
  - errors
  - escalations
  - approval requests
  - kill-switch events
  - the daily report
- **Daily report:**
  - trades
  - P&L
  - win rate
  - largest loss
  - Jev's average and p95 latency, and cost per decision
  - Brier and BSS per question
  - risk rejections by reason

## 15. VPS deployment

- **Base system:** Ubuntu LTS.
- **systemd units:**
  - `trader.service`, `watchdog.service` and `dashboard.service`, each with `Restart=always` and `RestartSec=5`
  - `nightly.timer`, which runs `brain` and then `harness`
- **Secrets:**
  - `/etc/lastairplane/<user>.env`, mode `0600`, owned by each service user.
  - Logs pass through a redaction filter. A test asserts that no key pattern ever appears in log output.
- **Firewall:** `ufw` denies all inbound traffic except SSH (key-only).
- **Egress:** allow-listed per user (via iptables owner match).
- **Backups:** the SQLite event log is backed up nightly.
- **Deploys:**
  - Each deploy is a git tag.
  - Rollback means checking out the previous tag and restarting.
  - The trader refuses to start if `MODE=live` without the signed checklist file (section 17).

## 16. Test-first build order (Gate 3 will expand this into the plan)

Each module ships with failing tests first, a review against this document, and a rollback path. The order is chosen so that **risk is built before anything that can trade**:

1. `config/limits` and `risk/`:
   - a blocking test for **each** hard limit, including the boundaries $500.00 vs $500.01 and $1,000.00 vs $1,000.01
   - kill switch
   - HALT persistence
2. `ledger/` and reconciliation, including the mismatch → HALT test.
3. `data/` and `state/`, including the lookahead property test and the bar-timestamp convention test.
4. `strategy/` rules and `backtest/`, including costs, DSR (checked against published examples), the trial registry and the holdout vault's access control.
5. `reflex/`, including fail-closed behaviour on timeout and schema error, and the veto-only property.
6. `calibration/`, including labels, metrics checked against known synthetic cases, and recalibrator split hygiene.
7. `execution/`, `approval/` and `watchdog`, including idempotency, default-deny, and flatten-on-silence.
8. `alerts/`, `dashboard/`, `reports/` and `brain/`, including the import-boundary contract test.

## 17. Go-live checklist (enforced in code at startup when MODE=live)

The checklist is the spec's final-check list. Each item needs evidence:

- **Paper vs backtest:** paper results fall within the backtest's distribution (a test on trade-level returns).
- **Kill switch:** it fired in testing, as evidenced by the paper event log.
- **Hard limits:** no limit is delegated to a model, as evidenced by the import-linter and limit-schema tests.
- **Calibration:** calibration is verified on our own fills (section 7.4 B).
- **Breaking regimes:** the market regimes that would break the strategy have been documented.
- **PDT:** the PDT rule has been resolved.
- **Approval:** you sign it.

The final section of the go-live document is **"WHAT COULD BLOW UP THIS ACCOUNT?"**. Live deployment is refused until every answer is clean.
