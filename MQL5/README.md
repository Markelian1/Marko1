# CRT MTF EA (MT5)

Expert Advisor për MetaTrader 5, i ndërtuar nga indikatorët TradingView
"CRT MTF EVENT ENGINE v8 - 5M FINAL - NO 1M" dhe "v5 + v6 1M MICRO ENGINE".
Vlerat fillestare janë zgjedhur për **XAUUSD**.

Skedari: `Experts/CRT_MTF_EA.mq5` (v1.26)

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

## Parametrat (v1.26, vlerat fillestare)

Vlerat fillestare janë konfigurimi i zgjedhur nga optimizimet 2023–2026.
Kur e vendos EA-në në grafik (ose shtyp **Reset** te Inputs), nuk ke nevojë të ndryshosh asgjë.

| Grupi | Parametri | Vlera | Çfarë bën |
|---|---|---|---|
| 1. STRATEGY | Entry mode | CRT close | hyn kur konfirmohet CRT-ja |
| | CRT entry timeframe | **15 Minutes** | CRT-ja që jep hyrjen |
| | HTF bias filter | **Require an active HTF CRT in the same direction** | hyn vetëm në drejtimin e CRT-së së HTF-së |
| | HTF bias timeframe | **1 Day** | CRT-ja ditore jep drejtimin |
| 2. RISK | Risk per trade | 0.5% | humbja nëse preket SL-ja |
| | Max lots | 5.0 | kufi sigurie |
| | Max trades per day | 3 | |
| 3. STOP / TARGET | Stop loss placement | CRT sweep wick (C2) | SL përtej wick-ut + 0.30 $ |
| | Take profit | CRT target | ana tjetër e parent range |
| | Min reward:risk | 1.0 | trade-t me RR < 1 anashkalohen |
| | Move SL to entry at +R | 0 (fikur) | break-even-i doli më keq në optimizim |
| | Close when CRT invalidated | true | del kur CRT-ja prishet |
| 4. FILTERS | Min SL | 1.00 $ | stop-et shumë të vegjël anashkalohen |
| | Min SL × spread | 4 | spread-i ≤ 25% e rrezikut |
| | Min sweep | 10% e range-it | sweep-et prej disa centësh anashkalohen |
| | Max spread | 0.50 $ | |
| 5. SESSION | Session | 10:00–20:00 (ora e serverit) | Londër + New York |
| 6–9 | Motori, 1M micro, paneli, optimizimi | – | nuk kanë nevojë për ndryshim |

## Kufizimet

- Nuk ka filtër lajmesh (NFP, CPI, FOMC). Gjatë lajmeve ari lëviz shumë,
  ndaj përdor `InpUseSession` ose fike EA-në manualisht.
- Orari i sesionit është në kohën e serverit të brokerit, zakonisht GMT+2/+3.
- Mbahet vetëm një pozicion njëherësh për çdo simbol dhe magic number.
- Rezultatet e backtest-it nuk garantojnë fitim. Testoje fillimisht në llogari demo.

## Optimizimi (v1.23): testi i organizuar

Skedari `Presets/CRT_MTF_EA_optimize.set` përmban matricën e testit:

| Parametri | Vlerat që testohen |
|---|---|
| `InpEntryTF` | M5, M15, M30, H1 |
| `InpBiasMode` | Off, "Block against", "Same direction" |
| `InpBiasTF` | H1, H4 (duhet të jetë mbi timeframe-in e hyrjes) |
| `InpCloseOnInvalid` | true, false |
| `InpBreakEvenR` | 0 (fikur), 1.0 |

Janë 72 kombinime të vlefshme. Kombinimet e pavlefshme (M6, M10, H2 etj.)
anashkalohen menjëherë.

**Hapat:**
1. Kopjo `CRT_MTF_EA_optimize.set` te `MQL5/Profiles/Tester/`.
2. Strategy Tester → **Settings**:
   - Expert: `CRT_MTF_EA`, Symbol: XAUUSD, Timeframe: M5
   - Date: **2023.01.01 – 2026.09.26**
   - **Forward: Custom, 2025.07.01**. Periudha para kësaj date përdoret për zgjedhjen,
     ajo pas saj për vërtetim.
   - Modeling: **1 minute OHLC**
   - Optimization: **Slow complete algorithm**, kriteri: **Custom max**
     (profit factor, vetëm për kombinimet me ≥ 100 trade)
3. **Inputs** → klik i djathtë → **Load** → `CRT_MTF_EA_optimize.set`
4. **Start**. Kur të mbarojë, dërgo skedat **Optimization Results** dhe **Forward Results**.

**Si lexohet:** një kombinim ia vlen vetëm nëse ka **PF > 1.1 edhe në periudhën
forward** dhe të paktën 100 trade. Një PF i mirë vetëm në periudhën e parë
nuk mjafton: mund të jetë thjesht përshtatje me të kaluarën.

## Rezultatet e optimizimit dhe kandidati v1.25

Optimizimi 2 (vetëm "Require an active HTF CRT in the same direction"):

| Hyrja | Bias | Periudha 1 (2023 – qershor 2025) | Forward (korrik 2025 – shtator 2026) |
|---|---|---|---|
| M15 | D1 | PF 0.87 (306 trade) | **PF 1.39–1.41** (~185 trade) |
| H1 | D1 | PF 0.91–0.94 (103 trade) | PF 1.36–1.71 (39 trade) |
| H1 | H4 | PF 0.85–0.89 (112 trade) | PF 1.44–1.45 (47 trade) |
| M30 | H4/D1 | PF 0.62–0.79 | PF 0.83–1.09 |

- Çdo variant M15/H1 me bias H4/D1 në të njëjtin drejtim **humbi në periudhën 1
  dhe fitoi në forward**. Avantazhi varet nga kushtet e tregut (regjimi).
- Asnjë kombinim nuk e kaloi rregullin "PF ≥ 1.0 në periudhën 1".
- Parazgjedhjet e v1.25 janë familja më e mirë: **M15 + D1 same direction**.
  Përdore **vetëm në demo** derisa ta vërtetojmë.
