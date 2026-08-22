# XAUUSD Donchian Trend EA (MQL5)

Expert Advisor for MetaTrader 5 trading Gold (XAUUSD). Signals are generated on
**H4**, while trade management / trailing runs on **M30**.

## Strategy

| Block | Rule |
|-------|------|
| **Entry** | Donchian Channel (20) breakout. Close above upper band = Buy, below lower band = Sell. |
| **Filters** | Price on trend side of SMA(50); ADX(14) > 20. |
| **Sizing** | Risk 1% of balance vs. SL distance. Works on standard and **Cent** accounts (uses tick value in deposit currency). |
| **Exit** | No fixed TP — SL only, profit runs via trailing. |
| **Break-even** | Move SL to entry (+buffer) once profit reaches **0.25R**. |
| **Partial close** | Close **40%** of the position at **1R**. |
| **Trailing** | All layers run together; the **safest** (most protective) stop is chosen: ATR(18)×5.75, Strong-Move ATR(12)×2.75, Mini-Strong ATR(16)×2.0, swing high/low, and the 3rd candle back. SL is only ever tightened. |

## Protection

- **Max Drawdown 20%** → pauses the EA in real time; auto-resumes when DD recovers
  below the threshold (with a small hysteresis buffer).
- **Daily Drawdown 1.5%** → stops opening trades for the rest of the day; resets next day.
- **News filter** → no new trades within **±90 min** of high-impact events
  (uses the MT5 economic calendar; currencies configurable, default `USD,XAU`).

## Confidence system

Lot size is scaled **0.5x–2.0x** based on the win rate and profit factor of the
last 10 closed trades, smoothed with an EMA factor of **0.25**.

## Notifications

Push notifications (`SendNotification`) are sent on every event: trade open/close,
partial close, break-even, drawdown warnings, news on/off, and EA start/stop.
Configure your MetaQuotes ID in *Tools → Options → Notifications*.

## Install

1. Copy `XAUUSD_Donchian_EA.mq5` into `MQL5/Experts/`.
2. Open it in MetaEditor and press **Compile** (F7).
3. Attach to an **XAUUSD H4** chart and enable *Algo Trading*.

All thresholds, periods and multipliers are exposed as inputs.

---

# Elliott Wave Dual Swing EA (MQL5)

`Metasit_ElliottWave_DualSwing_EA.mq5` — trades **with the trend, on the pullback**,
using Elliott wave structure to decide where the pullback ends. Long and short.

| Block | Rule |
|-------|------|
| **Structure** | Two ZigZag passes on the same series: a coarse one for the major swing (P0 → P1 → P2) and a fine one for the sub-waves (1-2-3-4-5 and a-b-c). Written in-file, no `iCustom` dependency, no repainting (pivots are depth-confirmed; one provisional pivot tracks the swing that is still forming). |
| **Filter** | ADX above threshold on **three** independent timeframes at once (H4/H1/M15 by default). Switchable off. |
| **Phase 1** | Impulse rules: wave 2 ≤ 87.5% of wave 1, wave 3 beyond wave 1 and never the shortest of 1/3/5, wave 4 overlap ≤ 60%, wave 5 beyond wave 3. |
| **Phase 2** | Correction rules: a beyond wave 4, b a lower high vs P1, c ≤ 78.5% of P0→P1 and never past P0. Draws `c = P2 (Buy/Sell Zone)` when they coincide. |
| **Entry** | *Mode 1* market entry on a reversal bar at P2 (pin bar / engulfing / HH+HL, mirrored for shorts). *Mode 2* ladder of 1-3 Limit orders at Fib 61.8 / 78.6 / 81.0% of P0→P1. |
| **Exit** | TP at Fib extension (161.8% by default) or fixed points; SL beyond P2 / beyond Fib 78.5% / fixed points. |
| **Trailing** | Step trailing: at +500 points lock +300, then move the stop +200 for every further +200. Tightens only. |
| **Sizing** | Risk % per setup (split across the ladder) or fixed lots. No martingale, no averaging, SL on every order. |

Both directions run through **one** rule engine, normalised by a `dir` (+1/-1) factor,
so the short side cannot drift out of sync with the long side.

- Guide (Thai): `คู่มือ_Elliott_Wave_Dual_Swing.md`
- Presets: `EW_DualSwing_DEFAULT.set`, `EW_DualSwing_XAUUSD_WIDE.set`
- Offline logic tests: `tests/ew_dual_swing/run.sh`
