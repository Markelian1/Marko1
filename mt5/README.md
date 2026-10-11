# LiquidityATR_EURUSD — robot MT5

Robot i ri (MQL5) për EURUSD. **Nuk është LPX.** Kodi i LPX nuk është publik; ky robot përdor të njëjtat
emra parametrash (`ATR_Period`, `ATR_Mult`, `ATR_RR`, `LiquidityHour1/Min1`, `LiquidityHour2/Min2`,
`RiskPercent`, `TradeFriday`, `UseNewsFilter`) që skill-i `lpx-set-analyzer` ta lexojë direkt XML-në e optimizimit.
Vlerat fillestare janë ato të set-it nga video (ATR 16 / 2.6 / 2.4, 14:10–14:20), por ato u gjetën për NDX me LPX —
për EURUSD duhen optimizuar nga e para.

## Si tregton

1. **Range-i i likuiditetit** (ora e serverit): qirinjtë nga `LiquidityHour2:LiquidityMin2` deri te
   `LiquidityHour1:LiquidityMin1`. Nëse `LiquidityHour2 = -1` (ose fillimi s'është para fundit), range-i është
   vetëm qiriri i fundit para `LiquidityHour1:LiquidityMin1`.
2. **Hyrja**, brenda `EntryWindowMin` minutave pas range-it:
   - `EntryMode = 0` — breakout: Buy Stop mbi majën e range-it, Sell Stop nën fundin; kur hapet njëra, tjetra fshihet.
   - `EntryMode = 1` — sweep: qiriri kalon majën/fundin e range-it dhe mbyllet përsëri brenda → hyrje në drejtimin e kundërt.
3. **SL = ATR × `ATR_Mult`**, **TP = SL × `ATR_RR`**, loti llogaritet që humbja në SL = `RiskPercent` % e balancës.
4. **Maksimumi 1 trade në ditë.** Me `CloseAtTime = true` gjithçka mbyllet në `CloseHour:CloseMin` (22:45) —
   pa pozicione gjatë natës ose fundjavës.
5. Filtra: `TradeFriday`, `MaxSpreadPoints`, `UseNewsFilter` (lajme të rëndësishme EUR + USD, ±`NewsMinutes`).
   **Filtri i lajmeve punon vetëm live/demo** — Strategy Tester s'ka kalendar ekonomik, prandaj e lëmë `false`
   që backtest-i dhe live të jenë njësoj.

## Instalimi

1. MT5 → **File → Open Data Folder** → kopjo `Experts/LiquidityATR_EURUSD.mq5` te `MQL5/Experts/`
   dhe `Presets/LiquidityATR_EURUSD_optimize.set` te `MQL5/Presets/`.
2. Hape `.mq5` në **MetaEditor** dhe shtyp **F7 (Compile)**. Nëse del ndonjë gabim, dërgoje këtu.

## Optimizimi → skill-i

Strategy Tester (Ctrl+R):

| Fusha | Vlera |
|---|---|
| Expert | LiquidityATR_EURUSD |
| Symbol / Period | EURUSD, **M10** |
| Date | 2024.01.01 – sot |
| Forward | **1/2** |
| Modelling | 1 minute OHLC (për shpejtësi) |
| Optimization | Fast genetic based algorithm |
| Kriteri | **Profit Factor max** (skill-i e kërkon këtë) |
| Inputs | right-click → **Load** → `LiquidityATR_EURUSD_optimize.set` |

Kur mbaron: skeda **Forward** → right-click → **Export to XML** → dërgoje XML-në këtu dhe skill-i zgjedh set-in.

Pastaj: backtest i vetëm i set-it të zgjedhur me **Every tick based on real ticks** → right-click te raporti →
**Save as Report → Excel (.xlsx)** → dërgoje këtu për validim.

## Kujdes

- Ora e serverit: shumica e brokerëve GMT+3 verë / GMT+2 dimër. London open ≈ 10:00, NY ≈ 15:30–16:30 server.
- Asnjë robot nuk garanton fitim. Provoje në **demo** para çdo llogarie reale ose prop firm.
