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
