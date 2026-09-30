# CRT MTF EA (MT5)

Expert Advisor për MetaTrader 5, i ndërtuar nga indikatorët TradingView
"CRT MTF EVENT ENGINE v8 - 5M FINAL - NO 1M" dhe "v5 + v6 1M MICRO ENGINE".
Vlerat fillestare janë zgjedhur për **XAUUSD**.

Skedari: `Experts/CRT_MTF_EA.mq5` (v1.20)

## Pse v1.10 humbi rreth 48% në 5 javë (XAUUSD M5, 2023)

Nga journal-i i testit:

- Stop-et ishin shumë të vogla: $0.32–$1.09. Spread-i ishte $0.18–$0.26,
  pra **20–50% e rrezikut të çdo trade-i shkonte te spread-i**.
- Me rrezik 0.5% dhe stop kaq të ngushtë, lotet dilnin 2.8–5.
- Shumë "sweep" ishin vetëm disa cent mbi/nën parent range, pra zhurmë
  dhe jo marrje likuiditeti.
- Pa limit ditor (14+ trade në ditë) dhe me trade edhe në 22:00–23:30
  (rollover, spread i gjerë), kostoja shumëfishohej.

Me këto kosto, një stop dhe target kaq afër janë matematikisht humbës,
pavarësisht nga ideja e CRT-së.

## Si funksionon

1. Shtatë motorë CRT (1W, 1D, 4H, 1H, 30M, 15M, 5M) punojnë vetëm me qirinj
   të mbyllur: parent → sweep → mbyllje brenda range-it → CRT.
2. **v8, modaliteti fillestar (`ENTRY_CRT_CLOSE`)**: kur mbyllet CRT-ja 5M,
   hapet trade me çmim tregu.
   - **SL** përtej wick-ut të qiririt që bëri sweep-in (C2) + buffer
   - **TP** te target-i i CRT-së 5M (ana tjetër e parent range), ose R fiks
   - Nëse CRT-ja 5M invalidohet (mbyllje jashtë parent range) ndërsa trade-i
     është hapur, trade-i mbyllet (`InpCloseOnInvalid`).
3. **Modaliteti opsional `ENTRY_MICRO_1M`**: pas CRT-së 5M, EA-ja pret në 1M
   sweep → MSS → FVG → retest dhe hyn te retest-i, me SL përtej sweep-it 1M.
   Shërben për të krahasuar nëse filtri 1M sjell ndonjë përfitim.

## Çfarë u rregullua nga versioni Pine

| Problemi në Pine | Në EA |
|---|---|
| Rregulli 50% ishte i kthyer mbrapsht (bull: `low <= 50%`) | Si parazgjedhje entry mbyllet kur çmimi ka bërë 50% të rrugës **drejt target-it**. Rregulli v5 mbetet si opsion. |
| Eventet zbuloheshin me `!=` kundrejt `na` | Eventet vijnë direkt nga motori |
| 5M vinte me një bar vonesë (`[1]` në chart 5M) | Motori 5M punon me qirinj M5 të mbyllur, pa vonesë shtesë |
| Historia 1M fshihej te çdo CRT e re | Historia 1M është e vazhdueshme, ndaj sweep-i mund të ndodhë te qiriri i parë |
| `MSS Lookback` nuk përdorej | Sweep-i dhe MSS kanë lookback të veçantë |
| Motori 1M mund të hynte pasi ishte prekur target-i | Target-i dhe 50% kontrollohen në çdo qiri 1M |
| Qiriri 1M që po formohej shkaktonte repaint | Përdoren vetëm qirinj 1M të mbyllur |
| Ledger-i ruante TARGET/INVALID me nivelet e reja | Ledger-i ruan nivelet e CRT-së që sapo u mbyll |

## Instalimi

1. Kopjo `Experts/CRT_MTF_EA.mq5` te `MQL5/Experts/` e terminalit
   (MT5: File → Open Data Folder).
2. Hape në MetaEditor dhe shtyp **F7** për ta kompiluar.
3. Tërhiqe EA-në mbi grafikun XAUUSD. Timeframe-i i grafikut nuk ka rëndësi;
   M5 është më i miri për ta ndjekur vizualisht.

> Kodi **nuk është kompiluar** në mjedisin ku u shkrua, sepse aty nuk ka
> MetaEditor. Nëse F7 jep gabime, dërgoji dhe rregullohen.

## Testimi në Strategy Tester

- Symbol: XAUUSD (ose emri që përdor brokeri, p.sh. `XAUUSD.m`, `GOLD`)
- Modeli: **Every tick based on real ticks**, ose të paktën **1 minute OHLC**.
  Mos përdor "Open prices only", sepse EA-ja punon me qirinj 1M.
- Visual mode: shfaq nivelet 5M, eventet 1M dhe panelin.
- Për krahasim, testo si `ENTRY_CRT_CLOSE` (v8) ashtu edhe `ENTRY_MICRO_1M`.

## Parametrat kryesorë

| Parametri | Vlera fillestare | Shpjegim |
|---|---|---|
| `InpTradeEnabled` | true | false = vetëm sinjale/alarme, pa trade |
| `InpEntryMode` | 5M CRT close (v8) | ose 1M micro |
| `InpEntryTF` | M5 | timeframe-i i CRT-së që jep hyrje: M5, M15, M30, H1, H4 |
| `InpMinSL` | 1.00 | stop-i minimal në $; setup-et me stop më të vogël anashkalohen |
| `InpMinSLSpreadX` | 4.0 | stop-i duhet të jetë ≥ 4 × spread-i (spread-i ≤ 25% e rrezikut) |
| `InpMinSweepPct` | 10 | sweep-i duhet të dalë ≥ 10% e range-it jashtë parent-it |
| `InpCloseOnInvalid` | true | mbyll trade-in kur CRT-ja 5M e tij invalidohet |
| `InpRiskPercent` | 0.5 | % e balancës që humbet nëse preket SL-ja |
| `InpSLMode` | 1M sweep | vetëm për 1M: sweep 1M, wick-u C2, ose FVG. Në 5M SL-ja është gjithmonë te wick-u C2 |
| `InpSLBuffer` | 0.30 | distanca shtesë e SL-së, në $ për XAUUSD |
| `InpTPMode` | CRT target | ose R fiks (`InpRMultiple`) |
| `InpMinRR` | 1.0 | trade-t me reward:risk më të vogël anashkalohen |
| `InpBreakEvenR` | 0 (fikur) | kalon SL-në te hyrja pas +R |
| `InpMaxTradesDay` | 3 | numri maksimal i trade-ve në ditë |
| `InpMaxSpread` | 0.50 | spread maksimal në $ |
| `InpUseSession` | true, 10:00–20:00 | orari është në **orën e serverit** të brokerit (Londër + New York) |
| `InpBiasMode` | off | filtër sipas CRT-së në një timeframe më të lartë |
| `InpMidRule` | toward target | rregulli 50%: drejt target-it, v5, ose i fikur |
| `InpSweepLookback` / `InpMssLookback` | 3 / 3 | numri i qirinjve 1M |
| `InpMicroMaxBars` | 15 | sa qirinj 1M pret pas CRT-së |
| `InpLedgerCSV` | false | ruan ledger-in te `MQL5/Files/CRT_ledger_<symbol>.csv` |

## Kufizimet

- Nuk ka filtër lajmesh (NFP, CPI, FOMC). Gjatë lajmeve ari lëviz shumë,
  ndaj përdor `InpUseSession` ose fike EA-në manualisht.
- Orari i sesionit është në kohën e serverit të brokerit, zakonisht GMT+2/+3.
- Mbahet vetëm një pozicion njëherësh për çdo simbol dhe magic number.
- Rezultatet e backtest-it nuk garantojnë fitim. Testoje fillimisht në llogari demo.
