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

---

# Testi i "CRT_MTF_MT5_TEST_V3" (kod i jashtëm, 5M CRT)

Rregullat e tregtimit të V3: hyrje me çmim tregu pas çdo CRT 5M të konfirmuar, SL te ekstremi i sweep-it
pa buffer, TP te ana tjetër e parent-it, pa filtra, 0.01 lot. U testua me `backtest/crt_backtest.py`
dhe historikun e FP Trading:

| Të dhënat | Trade | Në ditë | Win | PF | Mesatarja | 0.01 lot |
|---|---|---|---|---|---|---|
| M1, 2026.06–2026.10 (më i sakti) | 3 579 | 41 | 38.8% | 0.81 | −0.12R | −1 031 $ |
| M5, 2025.05–2026.10 | 17 749 | 40 | 37.9% | 0.77 | −0.15R | −4 713 $ |
| Të njëjtat rregulla, CRT M15 (2022–26) | 16 711 | 13 | 37.1% | 0.82 | −0.12R | −2 546 $ |
| Të njëjtat rregulla, CRT H1 (2022–26) | 3 680 | 3 | 36.9% | 0.89 | −0.07R | −979 $ |

Humb në çdo timeframe dhe në të dy gjysmat. Është e njëjta qasje si CRT_MTF_EA v1.10. SL mesatar është rreth 2.3 $,
prandaj spread-i (~0.2 $) merr ~10% të rrezikut në rreth 40 trade në ditë.

### Përmirësimet e provuara mbi V3

U testuan 32 kombinime mbi hyrjen e V3, d.m.th. hyrjen në mbylljen e CRT:
- filtrat e kostos (SL buffer 0.30, SL min 1 $ / 4× spread, spread max 0.50, sweep min 10%);
- trendi ditor SMA 50;
- CRT H4 ose D1 në të njëjtin drejtim;
- sesioni 01–13 NY;
- TP min 2R;
- hyrje në M5, M15 dhe H1.

| Më të mirat | Trade | PF (gjysma 1 / 2) |
|---|---|---|
| M5 + kosto + trend + CRT H4 + sesion (2025–26) | 520 | 1.03 (1.13 / 0.94) |
| M15 + kosto + trend + sesion + TP ≥ 2R (2022–26) | 543 | 1.05 (1.05 / 1.05) |
| **CRT_1AM_EA Combined (MT5, 2023–26)** | 788 | **1.37** |

Edhe me të gjitha filtrat, hyrja në mbylljen e CRT mbetet afër zeros. Avantazhi i CRT_1AM_EA vjen nga
hyrja te thyerja e OB në M15, brenda strukturës kohore H4, në drejtimin e trendit.

---

# Kërkimi i tregut: si sillet ari dhe çfarë mund të shtohet si "agjent"

Kërkimi në web dha tri ide të njohura:
- efektet e sesioneve, ku blerjet e Azisë zbehen në Londër/New York;
- momentumi i trendit (Moskowitz, Ooi & Pedersen 2012);
- reagimi pas sweep-eve të likuiditetit.

U testuan me historikun e FP Trading (M30, 2020.02–2026.09).

**1. Lëvizja sipas orës (NY).** Ora 18:00 (hapja e ditës së re) del pozitive në të tri periudhat
(+1.9 / +2.2 / +3.3 bp, t = 1.8 / 2.8 / 3.2). Sesioni i Azisë (18–02) mban pjesën më të madhe të rritjes:
+4.0 / +1.8 / +5.2 bp në ditë. Është efekt kohor, prandaj nuk u përdor (kërkesa: pa tregtim me orar).

**2. Trendi ditor.** Nuk parashikon në mënyrë të qëndrueshme 5 ditët e ardhshme. Në 2020–21 tregu kthehej mbrapsht,
në 2024–26 vazhdonte trendin. Vetëm, trendi nuk mjafton; si filtër i sweep-it funksionon.

**3. Agjentë klasikë pa orë** (`backtest/agents_lab.py`; 2020.02–2023.06 / 2023.07–2026.09):

| Agjenti | Periudha 1 | Periudha 2 |
|---|---|---|
| Pullback RSI-2 në trend, H1 | PF 0.88–0.92 | PF 0.92–0.94 |
| Pullback RSI-2 në trend, H4 | PF 0.98–1.03 | PF 1.05–1.10 |
| Breakout Donchian 20/55, H1/H4 | PF 0.73–0.90 | PF 1.27–1.89 |
| Breakout NR7 ditor në trend | PF 1.32 (67 trade) | PF 1.72 (66 trade) |

Donchian varet nga regjimi: humb në treg anësor, fiton në trend. NR7 është pozitiv në të dyja, por
me shumë pak trade (~20 në vit) për ta konsideruar të provuar. Avantazhi i qëndrueshëm mbetet te
**sweep-i i qiririt H4 + thyerja e OB-së + retest-i, në drejtimin e trendit** (PRO24).

---

# Testi i "SweepContinuation_PDH_PDL_MT5" (kod i jashtëm)

Logjika: breakout i high/low-it të ditës së kaluar (PDH/PDL) që mbahet. Hyrja bëhet me treg në mbylljen e qiririt
përtej nivelit. SL vendoset përtej qiririt të sinjalit + 1.5$, TP 2R, me filtër ATR(14) ≥ mesatarja e 50 qirinjve
dhe një trade në ditë. U simulua rresht për rresht me `backtest/pdh_continuation.py`.

| Grafiku | 2020.03–22.06 | 2022.07–24.06 | 2024.07–26.09 |
|---|---|---|---|
| M30, siç vjen (offset 0) | PF 0.85, −35R | PF 0.78, −50R | PF 1.08, +18R |
| M30, ora e saktë NY (offset −7) | PF 0.97, −8R | PF 0.90, −20R | PF 1.20, +48R |
| M30, ora NY + trendi ditor | PF 0.95, −5R | PF 0.98, −3R | PF 1.43, +57R |
| M15, siç vjen | – | PF 0.85, −37R | PF 1.04, +9R |
| M5 (2025.07–26.09), siç vjen / ora NY | | | PF 0.83 / 1.12 |

Fiton vetëm në 2024–26, kur ari ishte në trend të fortë rritës. Edhe kërkimi i 844 strategjive dha të njëjtën për
breakout-in e ditës së kaluar (PF 0.82–0.97 në 2020–23). Filtri i tij ATR, i provuar te CRT H4 jonë, e ul fitimin
(PF 1.09–1.27 në vend të 1.19–1.32). Nuk u fut asgjë prej tij.

Problemet e kodit:
- Me `InpServerToETOffset = 0` në FP Trading, "dita" fillon në 18:00 të serverit, pra 11:00 NY. Për NY duhet −7.
- Seanca `yyyymmdd − 1` jep p.sh. 20260300 ditën e parë të muajit. Kjo shkakton një rinisje të dytë të seancës,
  dhe atë ditë nuk tregton deri në 18:00.
- `PositionSelect(_Symbol)` dhe `PositionClose(_Symbol)` nuk e kontrollojnë magic-un. Pranë një EA tjetër (p.sh.
  GOLD MULTI PRO) ai nuk hap trade kur EA tjetër ka pozicion, dhe me time stop ose EOD mund ta mbyllë pozicionin e tjetrit.
- Kur loti i llogaritur është nën minimumin, vendos minimumin. Rreziku mund të kalojë 1%.
- Hyrja kontrollohet në çdo qiri mbi nivel, jo vetëm në thyerje. TP llogaritet nga mbyllja, jo nga çmimi i hyrjes.
- Nuk ka mbyllje të premteje, kufi ditor apo ndalim drawdown-i. Rreziku i parazgjedhur është 1%.

---

# Testi i "GOOGLE_STRATEG_XAUUSD" (kod i jashtëm) dhe GOOGLE STRATEG PRO

Logjika e v1.10:
- Range-i merret nga qirinjtë M15 11:30–14:30 të serverit, pra 04:30–07:30 NY.
- Në 14:30 vendoset një urdhër stop në drejtim të trendit H1, ku trendi H1 = mbyllja kundrejt EMA 200:
  buy stop te maja + 1.5 $, ose sell stop te fundi − 1.5 $.
- SL vendoset në mes të range-it (gjysma e range-it + 1.5 $), TP 3R, breakeven në +1R.
- Urdhri anulohet në 18:00. Rreziku është 1%.

U simulua rresht për rresht me `backtest/google_strateg.py`.

**Krahasimi me MT5 (2023.01–2026.09):** MT5 dha 627 trade (384 long, 243 short), PF 0.95, −12.7% dhe DD 32%.
Simulimi gjen 624 trade (382 / 242), pra hyrjet janë të njëjta. PF-ja varet nga qiriri i mbushjes. Me SL në mes,
në M15 nuk dihet nëse çmimi preku më parë hyrjen apo SL-në. Prandaj PF del 0.66 kur supozohet më e keqja
dhe 1.09 kur ndiqet rruga e qiririt. MT5 bie mes tyre. Kjo tregon edhe arsyen e humbjes: shumë thyerje kthehen
mbrapsht brenda pak minutash (sweep), pikërisht ajo që CRT-ja jonë kërkon për të hyrë në anën tjetër.

### Hap pas hapi (supozimi më i keq te qiriri i mbushjes)

| Varianti | 2020.03–22.06 | 2022.07–24.06 | 2024.07–26.09 | M5 2025.07–26.09 | M1 2026.06–09 |
|---|---|---|---|---|---|
| Siç vjen | PF 0.57, −101R | PF 0.53, −97R | PF 0.78, −52R | PF 0.93, −8R | PF 0.91, −2R |
| + trendi ditor (SMA 50 D1) në vend të EMA 200 H1 | PF 0.49, −112R | PF 0.58, −82R | PF 0.82, −41R | PF 1.05, +6R | PF 1.35, +7R |
| + pa breakeven | PF 0.60, −108R | PF 0.72, −72R | PF 0.96, −11R | PF 1.20, +30R | PF 1.37, +11R |
| + SL përtej gjithë range-it | PF 1.05, +12R | PF 1.06, +15R | PF 1.34, +87R | PF 1.46, +65R | PF 0.66, −13R |
| + range 15:00–17:00, anulim 21:00 (**v2.00**) | PF 1.18, +27R | PF 1.33, +44R | PF 1.46, +90R | PF 1.69, +75R | PF 0.60, −10R |
| v2.00 vetëm blerjet | PF 1.65, +45R | PF 1.61, +42R | PF 1.64, +89R | PF 2.01, +68R | PF 0.43, −8R |
| v2.00 vetëm shitjet | PF 0.77, −18R | PF 1.03, +2R | PF 1.01, +1R | PF 1.16, +7R | PF 0.82, −2R |
| Kontroll: pa breakout, hyrje në 17:00 sipas trendit ditor | PF 1.06, +26R | PF 1.22, +81R | PF 1.41, +162R | PF 1.54, +115R | PF 0.59, −23R |

Me SL përtej range-it, rezultati është i njëjtë në M1, M5 dhe M15. Prandaj këto shifra janë të besueshme.
Fqinjët e orarit (14:30–16:30, 15:30–17:30, anulim 19:00, 08:00–11:00) japin PF 1.13–1.79 në të tri periudhat.

**Kujdes:**
- Kontrolli pa breakout fiton po aq, dhe shitjet janë rreth zeros. Fitimi vjen kryesisht nga ndjekja e trendit
  ditor të arit, jo nga thyerja e range-it.
- Me TP 3R fiton vetëm rreth 31% e trade-ve, prandaj ndodhin 19 humbje rresht.
- Në 3 muajt e fundit (2026.06–09) ka dhënë −10R.

### Krahasimi me GOLD MULTI PRO (2020.03–2026.09)

| | Trade | Win | PF | R | DD (R) | R/DD | Humbje rresht | 0.1% rrezik |
|---|---|---|---|---|---|---|---|---|
| GOOGLE STRATEG siç vjen | 1 059 | 35% | 0.63 | −250 | 253 | – | 16 | −22.2%, DD 22.5% |
| GOOGLE STRATEG PRO v2.00 | 683 | 31% | 1.34 | +160 | 43 | 3.7 | 19 | +17.2%, DD 4.2% |
| GOLD MULTI PRO | 2 444 | 46% | 1.26 | +325 | 20 | **16.0** | 13 | +38.1%, DD 2.0% |

**Pse nuk u fut te GOLD MULTI PRO:**
- Fitimi rritet, por DD shkon nga 2.02% në 3.95% (me 11:30–14:30, në 5.10%).
- R/DD bie në 2020–22 dhe 2024–26.
- Është strategji me orar fiks.

E kundërta, d.m.th. hyrja në anën tjetër kur thyerja dështon (stil CRT), humb në dy nga tri periudhat
(PF 0.77 / 1.08 / 0.65). CRT H4 me retest OB-je në GOLD MULTI PRO e bën këtë ide më mirë.

### GOOGLE STRATEG PRO v2.00 (`Experts/GOOGLE_STRATEG_PRO.mq5`)

**Ndryshimet e rregullave:**
- Trendi është ditor (SMA 50 D1).
- SL vendoset përtej gjithë range-it.
- Pa breakeven.
- Range-i është 15:00–17:00 server (08:00–10:00 NY), anulimi në 21:00.
- Rreziku i parazgjedhur është 0.25%. Me 1%, DD-ja 2023–26 do të ishte rreth 25%.

Të gjitha rregullat e origjinalit mbeten si input-e (`InpTrend`, `InpSLMode`, `InpBreakeven`, oraret), që të
mund të krahasohen në MT5.

**Gabimet e origjinalit që u rregulluan:**
- Kur urdhri nuk vendosej (çmimi përtej hyrjes, pa trend, refuzim i Stops Level), `OnTick` dilte me `return`
  para `ManageActiveTrades`. Kështu breakeven-i nuk kontrollohej për pozicionet e hapura.
- Buffer-i ishte në "pips" (`_Point × 10`), që ndryshon me numrin e shifrave të brokerit. Tani jepet në dollarë.
- Mesazhet e gabimit përsëriteshin në çdo tick.

**Shtesat:**
- Ditari `Common\Files\GOOGLE_STRATEG_PRO_journal.csv` me arsyen e çdo hyrjeje: range-i, trendi në %,
  hyrja, SL, TP, dalja, R dhe $.
- Vizatimi i range-it dhe i niveleve, me tooltip.
- Panel me statusin dhe përmbledhje në fund të testit.

Kodi **nuk është kompiluar** këtu. Nëse F7 jep gabime, dërgoji.

### v3.00: ekzekutim në M5, me logjika të reja

Me `backtest/google_m5.py` u provuan **1 200 variante** mbi qirinj M5:
- 5 logjika hyrjeje, ku çdo vendim merret në mbylljen e qiririt M5;
- 5 orare range-i (11:30–14:30, 15:00–17:00, 16:30–17:00, 10:00–11:00, 01:00–09:00);
- 3 lloje SL-je, TP 1.5/2/3R, trendi D1/H1/pa trend, me dalje ose pa dalje në 23:00.

Logjikat:

| Logjika | Hyrja |
|---|---|
| close | qiriri M5 mbyllet përtej range-it (+0.50 $) → hyrje me treg |
| retest | pas asaj mbylljeje, limit te skaji i range-it |
| fvg | mbyllje përtej range-it që lë FVG → limit në mes të FVG-së |
| pullback | pas thyerjes, stop te qiriri i parë kundër saj |
| fade | qiriri del jashtë range-it dhe mbyllet brenda (sweep) → hyrje në anën tjetër |

Të dhënat M5 janë vetëm 2025.05–2026.09. Për më shumë histori u përdorën të njëjtat rregulla me qirinj M15
(2022.07–2025.04) dhe M30 (2020–22). Zgjedhja u bë vetëm me tri periudhat e para. **2026 mbeti jashtë
zgjedhjes.**

Vetëm dy logjika kaluan të gjitha provat:
- fitojnë në 4 periudhat;
- e mundin kontrollin pa sinjal;
- mbeten pozitive kur ndryshohen TP, buffer-i dhe ora ±30 min;
- japin rezultat të njëjtë kur hyrjet dhe daljet simulohen në M1 (2026.06–09).

FVG, pullback dhe fade prishen kur ndryshohet TP-ja ose ora (p.sh. FVG me TP 1.5–2R: PF 0.72–0.74 në 2025).

| Logjika (trendi ditor) | M30 2020–22 | M15 2022–25 | M5 2025 | **M5 2026** | Kontrolli pa sinjal |
|---|---|---|---|---|---|
| **1 NY CLOSE M5**: range 15:00–17:00 (08:00–10:00 NY), mbyllje M5 përtej, SL në mes, TP 3R, dalje 16:00 NY | PF 1.38, +17R | PF 1.46, +35R | PF 1.55, +17R | **PF 1.16, +7R** | 0.96 / 1.06 / 1.37 / 0.96 |
| **2 AZIA RETEST M5**: range 01:00–09:00 (18:00–02:00 NY), limit te skaji pas mbylljes përtej, SL përtej range-it, TP 2R | PF 1.15, +11R | PF 1.29, +41R | PF 1.56, +15R | **PF 1.64, +19R** | 0.89 / 1.10 / 1.25 / 1.06 |

Me rrezik 0.25%, 2020.03–2026.09:

| | Fitimi | DD maksimal | Vetëm M5 (2025.05–26.09) |
|---|---|---|---|
| v2.00 (urdhër stop) | +48.5% | 10.3% | +18.2%, DD 5.1% |
| 1 NY CLOSE M5 | +20.4% | **1.7%** | +5.8%, DD 1.4% |
| 2 AZIA RETEST M5 | +23.5% | 5.1% | +8.7%, DD 2.5% |
| **v3.00 = 1 + 2** | **+48.7%** | **3.9%** | +15.1%, DD 2.2% |

v3.00 jep të njëjtin fitim si v2.00, me më pak se gjysmën e DD-së.

**Me GOLD MULTI PRO** (0.1%, 2020–26):
- Logjika 1 e përmirëson në të tria periudhat: R/DD nga 5.0 / 6.4 / 6.5 në 6.2 / 7.6 / 8.9, fitimi nga +38.1% në
  +48.8%, DD nga 2.02% në 2.14%.
- Logjika 2 nuk e përmirëson (R/DD bie në 2020–22).
- Nuk u fut ende, sepse është me orar fiks. Mund të shtohet si modul nëse e do.

`Experts/GOOGLE_STRATEG_PRO.mq5` v3.00:
- `InpSignalTF = M5`.
- Logjikat 1 dhe 2 janë aktive, me magic 123460 dhe 123461.
- Logjika e v2.00 (urdhër stop) mbetet si logjika 3, joaktive, me magic 123462.
- Çdo logjikë ka oraret, buffer-in, SL-në, TP-në dhe daljen me orë si input-e.

Ditari ka kolonën "logjika", dhe arsyeja shkruan cili qiri M5 dha sinjalin dhe në ç'çmim u mbyll.

**Testi në MT5:**
- Grafiku XAUUSD M5, "Every tick based on real ticks", 2020.01–2026.09.
- Ky test kontrollon edhe vitet që këtu u testuan me M15 / M30.

---

# GOLD MULTI PRO (MT5): EA e re me 6 strategji dhe analizë për çdo trade

Skedari: `Experts/GOLD_MULTI_PRO.mq5` (v1.05), magic bazë **880100**.

**Testi MT5 i v1.00** (2023.01.01–2026.09.26, 0.1%): 1576 trade, PF 1.31, **+27.4%**, DD **1.87%**
(simulimi priste 1578 trade, +25.5%, DD 2.02%).

### v1.05: fotot kopjohen pranë ditarit edhe kur MT5 i shkruan me vonesë

Testi vizual i v1.04 ruajti **1576 foto**, por asnjë nuk u kopjua te Common. Terminali e shkruan foton pak pas
komandës, ndaj kopjimi i menjëhershëm gjeti skedar bosh. Fotot e atij testi janë në dosjen e agjentit:
`%APPDATA%\MetaQuotes\Tester\<ID>\Agent-127.0.0.1-3000\MQL5\Files\GOLD_MULTI_PRO_shots`.
Në v1.05 kopjimi provohet sërish çdo 5 minuta të testit dhe në fund (deri në 3 herë për foto).
Faqja e trade-ve tregon tani edhe emrin e fotos së çdo trade-i.

Testi vizual i v1.05 krijoi dosjen `GOLD_MULTI_PRO_shots`, por ajo mbeti bosh. Në Strategy Tester `ChartScreenShot`
kthen "sukses", por MT5 nuk e shkruan skedarin. Fotot punojnë vetëm në demo/live. Për testet, faqja e trade-ve ka
butonin **Luaj**: e riprodhon çdo trade qiri pas qiri, nga range-i deri te dalja, me shpejtësi 1x–8x, dhe kalon
vetë te trade-i tjetër (tasti Space e ndez dhe e ndal).

### v1.04: fotot nuk varen më nga skedari i ditarit

Testi vizual i v1.03 dha `SCREENSHOTS: none saved` dhe nuk pati rreshtin `GOLD MULTI JOURNAL`. Shkaku ishte se
`GOLD_MULTI_PRO_journal.csv` ishte i hapur në Excel: Windows e bllokon skedarin dhe EA nuk mund ta hapte. Në v1.03
vizatimet dhe fotot ishin të lidhura me ditarin, ndaj nuk u bë asgjë.

Në v1.04 vizatimet dhe fotot punojnë edhe pa ditar. Kur skedari është i bllokuar, ditari shkruhet te një skedar i ri
me datën në emër, p.sh. `GOLD_MULTI_PRO_journal_2026.10.01_22-40.csv`. Journal e tregon emrin e ri.

### v1.03: rreshti i fundit i testit tregon ku janë fotot

Në fund të çdo testi del rreshti `GOLD MULTI PRO v1.03 SCREENSHOTS:`. Ai tregon ose sa foto u ruajtën dhe rrugën
e plotë të dosjes, ose që testi u bë **pa Visual mode**. Pa Visual mode MT5 nuk vizaton grafik, prandaj nuk ka foto.

### v1.02: fotot ruhen pranë ditarit, dhe pamja e trade-ve

- Në v1.01 fotot u krijuan (ditari ka emrin e çdo fotoje), por MT5 në tester i ruajti në dosjen e agjentit:
  `%APPDATA%\MetaQuotes\Tester\<ID>\Agent-127.0.0.1-3000\MQL5\Files\GOLD_MULTI_PRO_shots`.
  Në v1.02 çdo foto kopjohet menjëherë te `Common\Files\GOLD_MULTI_PRO_shots`, pra pranë `GOLD_MULTI_PRO_journal.csv`.
- `backtest/trade_viewer.py` ndërton nga ditari një faqe HTML. Faqja vizaton çdo trade mbi historikun M15:
  qirinjtë, range-in e kohës, sweep-in, hyrjen, SL, TP, daljen dhe arsyen e EA-së. Ka filtra sipas
  strategjisë, rezultatit, drejtimit dhe vitit.

  `python3 trade_viewer.py ../reports/gold_multi_pro_mt5_journal.csv trades.html`
- Ditari MT5 i testit 2023–2026: `reports/gold_multi_pro_mt5_journal.csv`.

### v1.01: foto të çdo trade-i dhe pse blen kur range-i shkon poshtë

- Çdo trade i mbyllur vizatohet mbi grafik si "position tool": kuti e kuqe nga hyrja te SL, kuti e gjelbër
  nga hyrja te TP, vijë nga hyrja te dalja dhe rezultati (p.sh. `CRT 5AM +1.98R TP`).
- `InpShots` ruan foton PNG të grafikut për çdo trade: kur mbyllet (parazgjedhje), kur hapet dhe mbyllet,
  ose vetëm humbjet. Kjo punon në **Visual mode** të testerit dhe në demo/live.
  - Në tester fotot ruhen te `Tester\Agent-127.0.0.1-3000\MQL5\Files\GOLD_MULTI_PRO_shots`.
  - Në demo/live ruhen te `MQL5\Files\GOLD_MULTI_PRO_shots`.
  - Rruga e saktë del në Journal në fillim të testit ("Screenshots: ...").
  - Emri i çdo fotoje ka datën, pozicionin, strategjinë, drejtimin dhe rezultatin.
- Ditari `GOLD_MULTI_PRO_journal.csv` ka tani edhe kolonat "pozicioni", "foto hyrja" dhe "foto dalja",
  krahas strategjisë dhe arsyes së hyrjes.

**Pse blen kur range-i shkon poshtë?** Kjo është vetë logjika e CRT-së:
1. Range-i shitet dhe low-i i tij fshihet: merren stop-et e blerësve.
2. Kur një qiri mbyllet përsëri mbi order block-un, likuiditeti i marrë përdoret për të shkuar lart.
3. Roboti blen vetëm kur trendi ditor është lart.

U testua nëse ndihmon kërkesa që edhe drejtimi lokal të jetë lart:

| CRT H4 | 2022–24 | 2024–26 | 2020–22 | 2025–26 (M5) |
|---|---|---|---|---|
| v1.10 / GOLD MULTI | PF 1.32, +74R | PF 1.19, +68R | PF 1.21, +35R | PF 1.24, +50R |
| + dita e kaluar në të njëjtin drejtim | PF 1.36, +50R | PF 1.19, +39R | PF 1.05, +5R | PF 1.09, +11R |
| + qiriri i range-it në të njëjtin drejtim | PF 1.24, +15R | PF 1.16, +14R | PF 1.62, +20R | PF 1.14, +7R |
| + qiriri i range-it në drejtim të kundërt | PF 1.35, +59R | PF 1.21, +53R | PF 1.11, +15R | PF 1.27, +43R |
| + EMA 20/50 H4 në të njëjtin drejtim | PF 1.38, +66R | PF 1.11, +28R | PF 1.08, +10R | PF 1.07, +11R |
| + 24 orët e fundit në të njëjtin drejtim | PF 1.50, +42R | PF 1.18, +26R | PF 1.33, +19R | PF 1.22, +18R |

Pjesa më e madhe e fitimit vjen pikërisht nga blerjet pas një range-i që u shit. Filtrat heqin 40–80% të
fitimit, ndërsa PF-ja mbetet afërsisht e njëjtë. Humbjet e 23.09.2026 erdhën sepse trendi ditor ishte ende
lart. Të nesërmen trendi u kthye poshtë dhe roboti shiti (CRT 9AM SELL, TP).

## Si u ndërtua: kërkim në 844 strategji

`backtest/strategy_search.py` testoi **844 konfigurime nga 28 familje strategjish** mbi historikun
XAUUSD të FP Trading (M30, 2020.04–2026.09). Familjet:
- **trend**: MA cross, Donchian, Bollinger/Keltner breakout, Supertrend, MACD, ADX, Parabolic SAR,
  Ichimoku, Heikin-Ashi, TSMOM;
- **kthim te mesatarja**: RSI(2), z-score, Stochastic, CCI, N qirinj radhazi, qiri i madh, pivot S1/R1,
  blerje pas rënies;
- **breakout**: NR4/NR7, inside bar, squeeze, high/low i ditës ose i javës së kaluar;
- **price action / ICT**: engulfing, pin bar, outside bar, fair value gap, swing failure (sweep likuiditeti),
  Fibonacci 61.8%.

Rregullat e testit:
- Zgjedhje në 2020.04–2023.06 dhe gjykim në 2023.07–2026.09: duhen ≥ 40 trade dhe PF ≥ 1.15 **në të dyja**.
- Një "kontroll" pa sinjal (hyrje në drejtim të trendit në ritëm fiks) tregon sa jep vetëm trendi i arit:
  PF ≈ 1.0 në periudhën e parë dhe 1.1–1.3 në të dytën. Një strategji vlen vetëm nëse e kalon këtë.
- Të mbijetuarat u kontrolluan me çmime M15 dhe M5, dhe u futën vetëm kur e përmirësonin portofolin në
  2020–22, 2022–24 **dhe** 2024–26.

Çfarë doli:
- Shumica e strategjive klasike japin PF afër kontrollit, pra fitojnë vetëm sa jep trendi i arit.
- **FVG intraday** dukej shumë i mirë në M30 (PF 1.3), por ishte efekt i qirinjve të trashë: me renditjen e
  saktë (hyrja para SL-së në të njëjtin qiri) dhe me çmime M5, PF bie në 0.9–1.0.
- Mbetën tre module H4 që e përmirësojnë portofolin në të tri periudhat.

## Gjashtë strategjitë

| # | Strategjia | Logjika (pse hyn) | Dalja | Magic |
|---|---|---|---|---|
| 1 | **CRT H4** | range-i i qiririt H4 të mëparshëm fshihet (merren stop-et), një qiri M15 mbyllet përtej OB-së, hyrje në retest; trend, premium/discount, filtër volumi | TP 2R, 8h | +0..+5 |
| 2 | **CRT ditor** | e njëjta mbi qiririn ditor 17:00–17:00 NY, OB M30, retest 8h | TP 2R, 24h | +20 |
| 3 | **Inside day** | dita e djeshme brenda ditës para saj (energji e mbledhur), breakout M30 në drejtim të trendit | TP 2R, 24h | +30 |
| 4 | **Displacement** | qiri H4 ≥ 2.5× ATR: urdhra të mëdhenj hyjnë dhe zakonisht vazhdojnë | SL 1.5 ATR, TP 2R, 72h | +40 |
| 5 | **Bollinger pullback** | në trend, mbyllje H4 jashtë bandës dhe pastaj përsëri brenda: pullback i tepruar që kthehet | TP mesi i bandës, 72h | +50 |
| 6 | **CCI pullback** | në trend, CCI(20) H4 kthehet mbi −100 (nën +100): pullback-u mbaroi | kur CCI arrin ekstremin tjetër, 72h | +60 |

Simulim (`backtest/gold_multi_pro.py`):

| | 2020.03–22.06 | 2022.07–24.06 | 2024.07–26.09 |
|---|---|---|---|
| strategjitë 1–3 (si PRO24 v1.10) | PF 1.21, fitim/DD 3.7 | PF 1.31, fitim/DD 4.6 | PF 1.26, fitim/DD 6.2 |
| **të gjashta** | **PF 1.24, fitim/DD 5.0** | **PF 1.29, fitim/DD 6.4** | **PF 1.26, fitim/DD 6.5** |

| Rrezik 0.1% | Trade | Fitimi | Max DD |
|---|---|---|---|
| 2020.03–2026.09, strategjitë 1–3 | 1784 | +28.3% | 2.29% |
| **2020.03–2026.09, të gjashta** | **2444** | **+38.1%** | **2.02%** |
| 2023.01–2026.09, të gjashta (testi MT5) | 1578 | +25.5% | 2.02% |

## Analiza: pse u hap çdo trade

- Çdo hyrje shkruan në Journal rreshtin **ARSYEJA**: strategjinë, nivelet (range, sweep, OB, bandat, CCI),
  trendin ditor (% nga SMA50), volatilitetin (ATR ditor kundrejt 60 ditëve) dhe volumin e qiririt të fundit H4.
- E njëjta arsye ruhet në `Common/Files/GOLD_MULTI_PRO_journal.csv`, kolona "arsyeja e hyrjes (analiza)",
  bashkë me mënyrën si u mbyll trade-i.
- Mbi grafik, etiketa e çdo hyrjeje e tregon arsyen kur kalon mausin sipër (tooltip).
- Paneli tregon live **ANALIZA**: trendin, volatilitetin dhe volumin, si dhe gjendjen e çdo strategjie, p.sh.
  "qiriri i fundit H4 1.3x ATR (sinjal nga 2.5x)" ose "CCI(20) H4 −85".

## Pse nuk ekziston robot pa SL

Asnjë nga 844 konfigurimet nuk fiton çdo trade. Win rate më i lartë që u gjet ishte rreth 65% (RSI2 / qirinj
rënës me SL shumë të largët), dhe ato ishin me PF ≈ 1.0, pra pa fitim. Robotët që "nuk kapin kurrë SL" ose nuk
kanë SL, ose përdorin grid/martingale: humbjet i mbajnë hapur derisa një lëvizje e madhe e fshin llogarinë.
Këtu SL-ja është mbrojtja. Rreziku 0.1%, kufiri ditor 0.3% dhe ndalimi në 3.5% DD e mbajnë humbjen e vogël.

---

# CRT PRO24 (MT5): versioni 24 orë, pa orare fikse

Skedari: `Experts/CRT_1AM_PRO24.mq5` (v1.10). Është EA më vete; `CRT_1AM_EA.mq5` nuk preket.

- Ndjek **të 6 qirinjtë H4** të ditës (1AM, 5AM, 9AM, 1PM, 5PM, 9PM New York).
- Hyn **kur vjen setup-i**, në çfarëdo ore: sweep i range-it, pastaj një qiri M15 mbyllet përtej qiririt
  që bëri sweep-in dhe brenda range-it.
- Nuk ka key time, pauzë lajmesh apo dalje me orë.
- Filtrat: trendi ditor (mesatarja 50-ditore) dhe premium/discount i range-it.
- Dalja: SL përtej sweep-it, TP 1:2, mbyllje pas 8 orësh.
- E premtja në 16:00 NY mbyll trade-t (mbrojtje nga gap-i i fundjavës, `InpFridayClose = 0` e fik).
- Magic **770100**, pra mund të punojë krah CRT_1AM_EA (660100/660101).

### Si u zgjodh

U testuan kombinime pa orare fikse, me zgjedhje në 2022.07–2024.06 dhe kontroll në 2024.07–2026.09
dhe në 2020–2022 (M30):
- Hyrja M15 ose M30, OHLC on/off, trendi 50 ose 100 ditë: dallime të vogla.
- **Filtri i madhësisë së range-it** (ndaj ATR), që do të hiqte vetë qirinjtë e qetë si Asia: nuk qëndron.
- **Filtri i qiririt të lajmeve** (spike > 2–3× mesatarja), që do të zëvendësonte pauzën 8–10: nuk qëndron.
  Konfigurimet më të mira të periudhës së parë ranë në PF 1.05–1.07 në të dytën.
- **CRT mbi qirinjtë H1** (24 në ditë): humbës, PF 0.82–1.01. Hyrja M5: nuk përmirëson.

U mbajt varianti më i thjeshtë dhe më i qëndrueshëm.

### Rezultati (simulim, 2023.01.01–2026.09.26)

| | Trade | Win | PF | Total | Max DD | Fitimi |
|---|---|---|---|---|---|---|
| **PRO24, 0.5% rrezik** | 1226 | 42.6% | 1.17 | +112R | 11.1% | +71% |
| PRO24, 0.3% rrezik | 1226 | 42.6% | 1.17 | +112R | 6.8% | +39% |
| CRT_1AM_EA Combined, 0.5% | 787 | 47.0% | 1.40 | +151R | 6.5% | +109% |

PRO24 është pozitiv çdo vit (2023 +44R, 2024 +15R, 2025 +42R, 2026 +11R). Ka më shumë trade,
por më pak fitim për trade dhe rreth dyfish më shumë drawdown se versioni me orare.
Për të njëjtin drawdown si Combined, përdor rreth **0.3%** rrezik.

### Pas v1.10: çfarë u testua dhe nuk u fut

Kriteri mbetet i njëjtë: portofoli (PRO24 + Daily CRT + Inside day, 0.1%) duhet të dalë më mirë për të
njëjtin drawdown në çdo periudhë. Përndryshe nuk del version i ri.

| Ideja | Rezultati |
|---|---|
| CRT mbi qirinj 8h (Asia/Londër/NY), 12h, 2h si strategji shtesë | 12h e mirë në 2020–24, e dobët në 2024–26; asnjë nuk e përmirëson portofolin kudo |
| Breakout i qiririt inside H4, NR4 ditor | humbës ose i paqëndrueshëm |
| TP 2.5R / 3R / 3.5R / 4R, mbajtje 12h / 16h te PRO24 | 3R jep +34.5% në vend të +28.3% (2020–26), por DD 3.22% në vend të 2.29%; për të njëjtin DD del +24.5%, pra më keq |
| TP 2.5R / 3R te Daily CRT dhe Inside day | jo më mirë se 2R |
| Rrezik 1.5× kur volumi para hyrjes është > 1.3× mesatarja | +3–7% fitim/DD, shumë pak dhe jo monoton |
| CRT javor (java e kaluar, OB M30/H1/H4, retest 12–24h) | 15–43 trade në periudhë, pa avantazh |
| PRO24 pa re-entry | fitim/DD +7% (DD 2.09% në vend të 2.29%), por më keq në 2020–22 |
| Retest 2h/6h, SL buffer 0.10/0.60, premium/discount 60%/70%, OHLC, trend 20/100 ditë | asnjë më mirë kudo |

### v1.10: pa rregull me orë, filtër volumi në vend të tij

Testi MT5 i v1.09 (2023.01–2026.09, 0.1%): 1190 trade, PF 1.34, **+22.9%**, DD **2.00%**.
Sipas mënyrës: PRO24 944 trade +169.7R, Daily CRT 169 +23.4R, Inside day 77 +23.5R.

**Inteligjenca e testuar** (`backtest/liq_lab.py`; 4 periudha: dy gjysmat M15 2022–26, M30 2020–22, M5 2025–26):

| Ideja | PF | Përfundimi |
|---|---|---|
| Sweep i likuiditetit: majat/fundet H1 ose H4 (swing), OB, retest, trend (pa orë) | 0.71–1.34, negativ me M5 | pa avantazh |
| Range "rrëshqitës" 4h ose 8h në vend të qiririt H4 | 1.04–1.15 | shumë më i dobët |
| Volumi i sweep-it, zona me volum të lartë (volume profile), ana e POC | i ndryshëm nga periudha në periudhë | jo |
| Sweep që merr edhe likuiditetin H1 | më keq në të treja | jo |
| "Agjent" që fik llojin e setup-it pas një serie të keqe | më keq se rregulli fiks | jo |
| **Volumi i range-it** (likuiditeti i range-it që fshihet) | si rregulli i Asias | **u fut** |

Përfundimi kryesor: avantazhi vjen nga **struktura kohë–çmim e qirinjve H4** (PDF "Time & Price").
Sweep-i në vetvete, në çfarëdo ore, nuk mjafton.

**Filtri i volumit** (`InpMinRangeVol = 0.7`) zëvendëson rregullin me orë (`InpSkipAsia`, tani `false`):
- Një qiri tregtohet vetëm kur range-i i tij u ndërtua me të paktën 0.7 herë tick volume-in e një qiriri
  mesatar H4 të 5 ditëve të fundit.
- Sweep-i i një range-i ku nuk tregtoi askush nuk është marrje likuiditeti.
- Filtri heq rreth dy të tretat e qirinjve të Asias, por edhe qirinj të qetë në çdo orë tjetër.

| PRO24 + Daily CRT + Inside day, 0.1% | 2020.03–2026.09 | Max DD | 2023.01–2026.09 |
|---|---|---|---|
| v1.09, rregull me orë (pa 9PM) | +28.8% | 2.29% | +20.4% |
| **v1.10, filtër volumi** | **+28.3%** | **2.29%** | **+20.2%** |

Fitim/DD (R) sipas periudhave: v1.09 3.8 / 3.6 / 9.6; v1.10 3.7 / 4.6 / 6.2.
Pra v1.10 është më mirë në 2022–24 dhe pak më keq në 2024–26.

### v1.09: dy strategji të tjera në të njëjtin EA

Testi MT5 i v1.08 (2023.01–2026.09, 0.1%): 950 trade, PF 1.33, **+18.3%**, DD **2.18%**, 11 humbje radhazi,
ndalimi 3.5% nuk u prek.

Me `backtest/strategy_lab.py` u testuan 7 strategji shtesë, secila vetë dhe e kombinuar me PRO24, në tri periudha
(2020.03–22.06, 2022.07–24.06, 2024.07–26.09). Kriteri: PRO24 + strategjia duhet të ketë raport fitim/drawdown
më të mirë se PRO24 vetëm **në çdo periudhë**.

| Strategjia (vetë) | 2020–22 | 2022–24 | 2024–26 | Me PRO24 |
|---|---|---|---|---|
| Breakout NR7 | PF 1.28 | 0.96 | 2.31 | jo në çdo periudhë |
| **Breakout i ditës inside** | PF 1.38 | 1.23 | 3.40 | **më mirë në të treja** |
| Pullback EMA20 H4 / H1 | PF 0.98 / 0.88 | 1.10 / 0.94 | 0.92 / 1.10 | më keq |
| Donchian 20 H4 | PF 0.73 | 1.06 | 2.00 | më keq në 2020–22 |
| CRT ditor + OB H1 | PF 1.07 | 1.17 | 1.05 | i dobët |
| **CRT ditor + OB M30** | PF 1.16 | 1.31 | 1.29 | **më mirë në të treja** |

Variantet fqinje (TP 1.5–2.5R, mbajtje 24/48h, retest 4/8/12h, mbajtje 12/24/48h) mbeten pozitive.
Me çmime M15/M5 rezultatet mbeten të njëjta ose afër, sepse SL-të ditore janë të mëdha.

| Fitim/DD (R) | 2020–22 | 2022–24 | 2024–26 |
|---|---|---|---|
| PRO24 | 3.0 | 3.0 | 7.2 |
| **PRO24 + CRT ditor + inside day** | **3.8** | **3.6** | **9.6** |

Me 0.1% rrezik në 2020.03–2026.09: **+28.8% në vend të +19.9%, DD 2.29% në vend të 2.44%**.

- **Daily CRT** (`InpDailyCRT`, magic 770120): logjika e PRO24 mbi qiririn ditor 17:00–17:00 NY. Range-i është
  dita e kaluar, pastaj vjen sweep-i, thyerja e OB-së në M30 dhe retest-i deri në 8 orë.
  Filtrohet me trendin dhe premium/discount, ka TP 2R dhe mbyllet pas 24 orësh.
- **Inside day** (`InpInsideDay`, magic 770130): dje qëndroi brenda ditës para saj. Sot mbyllja e parë M30 mbi
  high-in e djeshëm (trend lart) ose nën low-in (trend poshtë) hyn me treg. SL është në anën tjetër të ditës
  së djeshme, TP 2R, mbyllje pas 24 orësh, një provë për çdo ditë inside.
- Rreziku, kufiri ditor dhe ndalimi i drawdown-it vlejnë për të gjitha. Secila strategji ka magic-un e vet
  dhe del veçmas në "SUMMARY by mode" dhe në ditar.

### v1.08: drawdown i ulët dhe ndalim automatik

Drawdown-i varet nga rreziku për trade; raporti fitim/drawdown është veti e strategjisë.
Një DD 0.01% nuk arrihet: edhe me lotin minimal 0.01, seria më e keqe e humbjeve (2020–26) ishte 140$,
pra 0.14% e 100,000$.

| Rreziku (v1.07, 2020.04–2026.09) | Max DD | Fitimi në vit |
|---|---|---|
| 0.5% | 11.2% | +24.8% |
| 0.3% | 6.8% | +12.2% |
| 0.2% | 4.6% | +7.4% |
| **0.1% (v1.08)** | **2.3%** | **+3.4%** |
| 0.05% | 1.2% | +1.6% |

Cilësimet e reja:
- `InpRiskPercent = 0.1`; në 2023.01–2026.09 jep +16% me DD maksimal 2.3%.
- `InpDailyLossPct = 0.3`: kufiri ditor mbetet rreth 3 humbje, si më parë.
- `InpMaxDDPct = 3.5` (**ndalimi automatik**): kur ekuiteti bie 3.5% nën majën e tij, EA mbyll trade-t,
  heq retest-et dhe ndalon. Drawdown-i normal pritet rreth 2.3–2.8%; 3.5% është tavani i fortë.
- Pas ndalimit, rinise me `InpResetDDStop = true` (maja bëhet ekuiteti aktual), pastaj ktheje në `false`.
- Jashtë testerit, maja dhe ndalimi ruhen në Global Variables të terminalit (F3), ndaj mbeten edhe pas rinisjes së MT5.
- Ekuiteti është ai i gjithë llogarisë. Pas një tërheqjeje parash, rinise me `InpResetDDStop = true`.
- Me 0.1%, trade-t me SL shumë të madh për llogari të vogla bien nën lotin minimal dhe nuk hapen
  (për 10,000$ rreth 15% e trade-ve; për 100,000$ pothuajse asnjë).

### v1.07: pa setup-et e Asias (qiriri 9PM)

Testi MT5 i v1.06: 1201 trade, PF 1.25, +129%, DD 11.2%, 712 humbje, 14 humbje radhazi.

U testuan rreth 25 ndryshime logjike në 4 periudha (2022.07–24.06 dhe 2024.07–26.09 në M15,
2020–22 në M30, 2025.07–26.09 me çmime M5). Simulatori u bë më i kujdesshëm: në qiririn ku
mbushet limiti nuk llogaritet TP (renditja e çmimeve brenda qiririt nuk dihet). Kështu
"retest më thellë 50%", që dukej PF 1.80 në M15, doli PF 1.07 me çmime M5.

| Ndryshimi | Rezultati |
|---|---|
| TP 1R / 1.5R / 3R, TP në anën tjetër të range-it | win rate ndryshon, fitimi jo më i mirë |
| SL më i gjerë (1.5$, 3$), soft stop me mbyllje M15 | më keq |
| Retest më thellë (25%, 50%), retest me konfirmim mbylljeje | më keq me çmime M5 |
| Trend më i fortë (pjerrësia e mesatares, SMA20/200 dakord) | jo i qëndrueshëm |
| Qiri thyerjeje i fortë, sweep i likuiditetit 12h/24h, premium/discount ditor | heq fitime sa humbje |
| Filtër volumi (tick volume) në thyerje ose sweep | më pak trade, jo më mirë për rrezikun |
| Mbajtje 4h ose 24h, mbyllje e pjesshme në 1R + BE | jo më mirë |
| Rrezik i reduktuar gjatë drawdown-it | njësoj si rrezik fiks më i ulët |
| **Pa qiririn 9PM (Asia)** | **më mirë në të 4 periudhat** |

Për çdo qiri H4 (PF në 4 periudhat): 9AM 1.54 / 1.38 / 1.66 / 1.22, 1PM 2.10 / 1.21 / 1.23 / 1.61,
**9PM 1.12 / 0.94 / 0.87 / 1.10**. Setup-et e Asias sjellin rreth 0R, por një të katërtën e humbjeve.
Në Asia likuiditeti është i hollë: sweep-i shpesh është fillimi i lëvizjes, jo kthimi.
Qiriri 9PM mbetet pjesë e range-it të 1AM; pesë qirinjtë e tjerë tregtojnë kur vjen setup-i.
`InpSkipAsia = false` e kthen si në v1.06.

| 2023.01–2026.09, 0.5% (simulim) | Trade | Humbje | Win | PF | Total | Fitimi | DD |
|---|---|---|---|---|---|---|---|
| v1.06 | 1147 | 678 | 40.9% | 1.22 | +145R | +101% | 10.0% |
| **v1.07** | 899 | **513** | 42.9% | **1.30** | +149R | +106% | 11.2% |

Fitimi mbetet i njëjtë me **165 trade humbëse më pak**. Drawdown-i maksimal nuk bie, sepse vjen nga seritë
e humbjeve të qirinjve të tjerë; atë e ul vetëm rreziku: 0.3% jep rreth 6–7% DD, 0.25% rreth 5.5%.

### v1.06: pa retest kundër trendit

Në testin MT5 të v1.05 (1134 trade, PF 1.24, +114%, DD 9.5%), Journal-i tregoi se nga 3451 retest-e
të vendosura, **1475 u refuzuan në mbushje sepse ishin kundër trendit**. EA e vendoste limitin pa e
kontrolluar trendin. Limiti rrinte deri në 4 orë dhe e zinte qiririn, kështu që një setup i mirë
në të njëjtin qiri nuk mund të vendosej. Në v1.06 trendi kontrollohet **para** se të vendoset retest-i.

| Simulim (spread +0.05) | 2022.07–24.06 | 2024.07–26.09 | 2020–22 (M30) | 2025–26 me çmime M5 |
|---|---|---|---|---|
| v1.05 | 521 tr, PF 1.29, +85R | 641 tr, PF 1.23, +87R | 440 tr, PF 1.17, +41R | 360 tr, PF 1.26, +55R |
| **v1.06** | 553 tr, PF 1.28, +88R | 681 tr, PF 1.25, +98R | 448 tr, PF 1.19, +46R | 378 tr, PF 1.25, +56R |

2023.01–2026.09, 0.5% rrezik (pa kufirin ditor): v1.05 1081 trade, PF 1.28, +131%, DD 8.6%;
**v1.06 1147 trade, PF 1.29, +144%, DD 8.3%**. Përmirësimi është i vogël, por del në çdo periudhë.
Në Journal, "against bias" tani numërohet kur vjen setup-i, jo në mbushje.

### v1.05: kontrolli i humbjeve

Testet në MT5 (2023.01.01–2026.09.26, 0.5% rrezik):

| | Trade | PF | Fitimi | DD | Humbje radhazi |
|---|---|---|---|---|---|
| v1.03 me Selective | 1184 | 1.27 | +141% | 9.2% | 13 |
| v1.04 pa orare | 1141 | 1.24 | +114% | 10.2% | 13 |

Rregullat e testuara për të ndalur humbjet, me kontroll në tri periudha dhe me çmime M5/M1:

| Rregulli | Rezultati |
|---|---|
| Trailing stop nga +1R, break-even në +1R | dukej mirë në M15, **por me çmime M5/M1 e përkeqëson** (efekt i qirinjve të trashë) |
| Ndalim pas 2 humbjeve në ditë, pauzë 24h pas 3–4 humbjeve radhazi, gjysmë rreziku pas humbjeve | ulin fitimin më shumë se humbjet |
| Maksimumi 1–2 trade të hapura | pa efekt: seritë e humbjeve vijnë njëra pas tjetrës, jo njëkohësisht |
| **Kufi ditor −1.5%** (`InpDailyLossPct`) | **fitimi i njëjtë, dita më e keq −1.5% në vend të −2.5%**: u fut si mbrojtje |

Humbjet janë të rastësishme dhe të pavarura; nuk ka një gabim të fshehur që hiqet me një rregull.
Mjeti që i zvogëlon drejtpërdrejt është **rreziku për trade** (`InpRiskPercent`):

| Rreziku | Fitimi 2023–26 | Max DD | 12 humbje radhazi | Dita më e keq |
|---|---|---|---|---|
| 0.25% | +53% | 4.3% | −3.0% | −1.2% |
| 0.30% | +66% | 5.2% | −3.6% | −1.5% |
| 0.40% | +96% | 6.9% | −4.8% | −2.0% |
| 0.50% | +131% | 8.6% | −6.0% | −2.5% |

### v1.04: pa tregtim me orar

`InpAddSelective = false` si vlerë fillestare: PRO24 nuk ka më asnjë hyrje me key time.
Rregulli i vetëm me orë që mbetet është **mbyllja e së premtes** në 16:00 NY (`InpFridayClose`).
Ajo nuk zgjedh kur hyhet; vetëm mbyll trade-t para fundjavës dhe nuk hap të reja në 4 orët e fundit.

| 2023.01–2026.09, 0.5% rrezik | Trade | Në javë | PF | Fitimi | Max DD | Trade-i më i keq |
|---|---|---|---|---|---|---|
| **v1.04 (me mbylljen e së premtes)** | 1081 | 4.7 | 1.28 | +131% | 8.6% | −1.8R |
| pa mbylljen e së premtes (`InpFridayClose = 0`) | 1104 | 4.8 | 1.29 | +136% | 8.4% | −3.6R |

Pa mbylljen e së premtes, 53 trade mbeten hapur gjatë fundjavës dhe gap-i i së hënës mund të kalojë SL-në.
Prandaj mbyllja mbetet e ndezur si mbrojtje.

### v1.03: më shumë hyrje

Mënyrat e testuara për më shumë hyrje (kontroll në 2022–24, 2024–26 dhe 2020–22):

| Ideja | Rezultati |
|---|---|
| **Një pozicion për çdo qiri H4** (secili qiri ka magic-un e vet) | ✅ më shumë trade dhe më shumë fitim |
| **Rihyrje në të njëjtin qiri** pasi mbyllet trade-i | ✅ më shumë trade, fitim i njëjtë |
| **+ Selective** (modeli i PDF-ve, magic +10) | ✅ edhe pak më shumë fitim |
| Pa filtër trendi | ❌ dyfish trade, por PF 1.04 dhe DD dyfish |
| Hyrje M5 | ❌ ndihmon një periudhë, dëmton tjetrën |

Inputet e reja: `InpPerCandle`, `InpReentry` (`true`) dhe `InpAddSelective` (`false` që nga v1.04).
Selective ka key time të PDF-së.

Simulimi 2023.01.01–2026.09.26, 0.5% rrezik për trade:

| | Trade | Në javë | PF | Fitimi | Max DD | Maks. të hapura |
|---|---|---|---|---|---|---|
| v1.02 | 922 | 4.0 | 1.29 | +107% | 9.8% | 1 |
| v1.03 pa Selective | 1081 | 4.7 | 1.28 | +131% | 8.6% | 2 |
| **v1.03 (fillestare)** | **1124** | **4.8** | **1.32** | **+161%** | **8.6%** | **3** |

Me 3 trade të hapura njëkohësisht, rreziku i përbashkët mund të arrijë 1.5% (0.5% secili).

### v1.02: hyrje me retest (limit te niveli i OB-së)

Kur një qiri M15 thyen OB-në, PRO24 nuk hyn më menjëherë. Pret deri në **4 orë** që çmimi të kthehet
te niveli i OB-së dhe hyn aty. Nëse çmimi kalon përtej sweep-it para kësaj, setup-i anulohet.
`InpEntryType = Market` e kthen sjelljen e vjetër.

Kombinime të tjera të testuara, me zgjedhje në një periudhë dhe kontroll në 2024–26 dhe 2020–22 (M30):
- **CRT ditore** (sweep i high/low të djeshëm, hyrje me OB në M15/M30/H1): pa avantazh, negative në 2020–22.
- **Retest te Selective**: më keq.
- **Retest te Active / PRO24**: më mirë në të tre periudhat, për çdo kohë pritjeje 1–8 orë.

| PRO24, mesatarja për trade | 2022.07–24.06 | 2024.07–26.09 | 2020–22 (M30) |
|---|---|---|---|
| hyrje market (v1.01) | +0.075R | +0.080R | +0.042R |
| **retest 4 orë (v1.02)** | **+0.148R** | **+0.128R** | **+0.098R** |

Për periudhën e testit në MT5 (2023.01.01–2026.09.26, 0.5% rrezik):

| | Trade | PF | Fitimi | Max DD |
|---|---|---|---|---|
| PRO24 v1.01 (market) | 1226 | 1.17 | +71% | 11.1% |
| **PRO24 v1.02 (retest)** | **922** | **1.29** | **+107%** | **9.8%** |
| CRT_1AM_EA Combined | 787 | 1.40 | +109% | 6.5% |

Retest-i heq kryesisht humbjet "kthim i menjëhershëm" (L1): nga 192 në 67.

### Ditari i trade-ve dhe pse humbet (PRO24 v1.01)

**Në MT5:** PRO24 shkruan çdo trade të mbyllur te
`Common\Files\CRT_PRO24_journal.csv` (`InpJournal = true`). Në fund të testit, Journal tregon rrugën e plotë.
Gjen dosjen edhe nga MT5: File → Open Data Folder, pastaj dy nivele lart → `Common\Files`.
Në tester skedari rishkruhet në çdo test; në demo/live trade-t e reja shtohen në fund.

**Në Python:** `backtest/loss_report.py` bën të njëjtën gjë me historikun e brokerit:
```
python3 loss_report.py --mt5 ../data/XAUUSD_M15.csv --mode pro24      # ose combined / active / selective
```
Rezultatet janë te `reports/pro24_trades.csv` dhe `reports/combined_trades.csv`.

Kolonat e skedarit:
- koha (server dhe NY), dita, qiriri H4, drejtimi;
- entry/SL/TP, SL në $, rezultati në R, dalja, minutat;
- **max në favor** dhe **max kundër** (në R): sa shkoi trade-i për ne dhe kundër nesh;
- range-i, sweep-i, pozicioni i hyrjes në range, trendi, SL/ATR, spread-i;
- **lloji** i fitimit/humbjes dhe një **përshkrim**.

| Lloji | Kuptimi |
|---|---|
| L1 | kthim i menjëhershëm: SL brenda 1 ore, pa lëvizje në favor (sweep-i vazhdoi) |
| L2 | pa drejtim: SL pas më shumë se 1 ore, pa lëvizje në favor |
| L3 | lëvizje e vogël në favor (+0.3R deri +1R), pastaj SL |
| L4 | fitim i humbur: arriti +1R e më shumë, pastaj SL |
| L5 | mbyllje me kohë në humbje |
| W1 / W2 | TP / mbyllje me kohë në fitim |

Rezultati për PRO24 (2023.01–2026.09, 1226 trade):
- L3 232 trade, L1 192, L4 120, L2 88, L5 72;
- W1 316 trade, W2 206.

Rregullat e testuara kundër këtyre humbjeve, me kontroll në të dy gjysmat dhe në 2020–2022:
- mbyllja e 50% në +1R me break-even (për L4);
- pa sweep-e më të thella se 50% e range-it;
- pa hyrje të premten;
- pa qiririn 9PM.

**Asnjë nuk qëndron:** ndihmon një periudhë dhe dëmton një tjetër. Humbjet janë kryesisht pjesë e natyrshme e strategjisë.
Ditari i demo-s do tregojë nëse në tregun live shfaqet ndonjë model i ri.

---

# CRT 1AM EA (MT5): strategjia nga PDF-të "1AM CRT" dhe "Time & Price"

Skedari: `Experts/CRT_1AM_EA.mq5` (v1.05). Është EA e re, e veçantë nga CRT_MTF_EA.
Nuk hap trade në çdo CRT, por vetëm në qiririn H4 të orës **1:00 New York** dhe
vetëm në orën kyçe.

## Rregullat e PDF-ve dhe si janë në EA

| Rregulli në PDF | Në EA | Input |
|---|---|---|
| Bias nga HTF (drejtimi ditor, DOL) | Trendi ditor: mbyllja e djeshme mbi mesataren 50-ditore = vetëm buy, nën të = vetëm sell | `InpBias`, `InpTrendDays` |
| Range-i kohor: qirinjtë 5PM + 9PM (Asia/CBDR) | High/low i 17:00–01:00 NY | automatik |
| Qiriri 1AM bën sweep të high/low të range-it (turtle soup) | Ndiqet çdo qiri M15 brenda 01:00–05:00 NY | automatik |
| OHLC / OLHC: sell mbi open, buy nën open | Sell vetëm kur çmimi është mbi open-in e qiririt 1AM | `InpOHLC` |
| Premium / discount | Sell vetëm mbi mesin e range-it kohor (Asia), buy vetëm poshtë tij | `InpPremDisc` |
| Ora kyçe 2:00–4:00 AM NY | Sinjali pranohet vetëm në këtë orar | `InpKT1From`, `InpKT1To` |
| Hyrja, modeli #1: qiriri që "gërmoi" mbi high-in, pastaj engulf | Qiriri me high-in më të lartë është OB; hyrje kur një qiri mbyllet nën low-in e tij dhe brenda range-it. Timeframe-i i hyrjes: **M30** (M15 si opsion) | `InpEntryTF` |
| SL përtej sweep-it | SL = maja e sweep-it + 0.30 $ | `InpSLBuffer` |
| TP 1:2 ose 1:3 | TP = 2R (mund ta bësh 3) ose ana tjetër e range-it | `InpTPMode`, `InpRR` |
| Modelet 5AM dhe 9AM (forex key times) | Të ndezura; maksimumi 1 trade në ditë për të tre modelet | `InpModel5AM`, `InpModel9AM` |

Nuk janë në EA: **SMT** (duhet simbol i dytë, p.sh. XAGUSD) dhe nivelet kyçe H4
(OB/FVG). Filtri premium/discount i zëvendëson pjesërisht.

## Ora e New York-ut (e rëndësishme)

EA-ja i llogarit të gjitha oraret në kohën e New York-ut:
`ora NY = ora e serverit − InpNYOffset`.

- Te shumica e brokerëve MT5 serveri është **NY + 7** gjatë gjithë vitit (GMT+2 në dimër,
  GMT+3 në verë), prandaj vlera fillestare është **7**.
- Kontroll: në MT5 hape **Market Watch**; ora lart është ora e serverit. Kur në New York
  është 00:00, serveri duhet të tregojë 07:00. Nëse jo, ndryshoje `InpNYOffset`.
- Te paneli i EA-së shfaqet "New York time"; duhet të përputhet me orën reale të NY.

## v1.05: a duhen oraret? Mënyra "Any time" (24h)

Testi i v1.04 Combined në MT5 (2023.01.01–2026.09.26): 788 trade, PF 1.37, +97%, DD 7.0%.
Rezultati ndahet në Active +115.5R dhe Selective +24.7R. Simulimi priste 787 trade dhe PF 1.40.

Pyetja ishte: a mund të hyjë EA-ja kur vjen setup-i, pa orare fikse? Mënyra e re
`InpMode = Any time` merr setup-in në **të 6 qirinjtë H4 të ditës** (edhe 5PM dhe 9PM, pra 24 orë),
pa key time dhe pa pauzën e lajmeve. Testi (2023.01.01–2026.09.26, 0.5% rrezik):

| | Trade | PF | Total | Max DD | Fitimi |
|---|---|---|---|---|---|
| **Combined (me orare)** | 787 | **1.40** | +151R | **13.3R** | **+109%** |
| Any time (24h) | 1226 | 1.17 | +112R | 23.4R | +71% |

Edhe në 2020–2022 (M30, të pavarura) "çdo orë" del më keq: PF 1.08 kundrejt 1.20.
Qirinjtë 5PM dhe 9PM nuk japin rezultat të qëndrueshëm: dalin pozitivë në një periudhë dhe negativë në tjetrën.
Rregulli i vetëm kohor që ndihmon gjithmonë është pauza e lajmeve 8:00–10:00 NY.

Oraret nuk janë hyrje me orë fikse. Brenda çdo qiriri H4, EA-ja hyn kur vjen setup-i
(sweep + thyerje e OB), në çdo minutë. Oraret vetëm tregojnë cilat qirinj H4 ndiqen.
Kjo është ideja e "Time & Price" te PDF-të.

## v1.04: mënyra Combined dhe pa hyrje në orën e lajmeve

Testi në MT5 i v1.03 Active (2023.01.01–2026.09.26) dha 857 trade, PF 1.21, +57%, DD 7.1%.
Simulatori për të njëjtën periudhë jep 856 trade dhe PF 1.25, pra EA-ja dhe simulatori përputhen.

Kërkesa e radhës ishte një kurbë më e rregullt. U testuan 12 ide. Dy kaluan edhe në të dhënat e
pavarura 2020–2022 (M30), që nuk u përdorën për t'i gjetur:

1. **Pa hyrje të reja 08:00–10:00 NY** (lajmet e SHBA-së në 8:30). Në 2020–2022 DD ra nga 18.5R në 12.7R.
2. **Active + Selective në të njëjtën EA** (`InpMode = Combined`). Secila ka magic-un e vet
   (Selective = magic + 1), pra mund të jenë hapur deri në 2 pozicione njëkohësisht.

Nuk kaluan dhe nuk u futën: break-even, TP 1.5, mbajtja 6/12 orë, kufiri 2–3 trade në ditë,
trendi i dyfishtë (50 & 20 / 50 & 100), kufiri i SL ndaj ATR dhe filtri i së enjtes.

Simulimi për 2023.01.01–2026.09.26 me 0.5% rrezik për trade:

| | Trade | Win | PF | Total | Max DD | Muaj pozitivë | Fitimi |
|---|---|---|---|---|---|---|---|
| v1.03 Active | 856 | 44.6% | 1.25 | +109R | 13.4R | 27/45 | +69% |
| v1.04 Active | 744 | 46.2% | 1.35 | +126R | 11.6R | 31/45 | +85% |
| **v1.04 Combined** | **787** | **47.0%** | **1.40** | **+151R** | **13.3R** | **33/45** | **+109%** |

Llogaria duhet të jetë **hedging**, që dy pozicionet të mos bashkohen në një.

## Laboratori i modeleve (`backtest/model_lab.py`): 52 kombinime

U testuan 52 modele në disa timeframe, me historikun M30 2020.02–2026.09 dhe kosto
= spread-i i brokerit + 0.10 $:
- **CRT klasik** (motori i CRT_MTF_EA) në M30, H1, H4, me dhe pa trend, me sesion ose gjithë ditën,
  me TP te target-i ose 1:2;
- **sweep i high/low të ditës së kaluar** (turtle soup) në M30 dhe H1;
- **breakout i range-it Asia** në drejtimin e daljes;
- **modeli H4 i PDF-ve** (Active dhe Selective, me dhe pa trend).

Rregulli: modelet zgjidhen **vetëm** me 2020.02–2023.06, pastaj gjykohen me 2023.07–2026.09.

| Familja | Rezultati |
|---|---|
| CRT klasik M30 / H1 / H4 (24 variante) | humbin: PF 0.77–1.06 |
| Sweep i ditës së kaluar (8) | humbin: PF 0.79–1.01 |
| Breakout Asia (16) | afër zeros: PF 0.82–1.13, humbës në periudhën e parë |
| **Modeli H4 i PDF-ve** | **i vetmi që kalon**; 3 variante, të tre pozitive edhe në periudhën e panjohur |

Kombinimi i modeleve humbëse nuk krijon fitim. Kombinimi i dobishëm është
**Active + Selective njëkohësisht**, në dy grafikë me magic number të ndryshëm.
Rezultati mbi M15 2022.10–2026.09, me spread +0.10 $:

| | Trade në ditë | Mesatarja | PF | R në vit | Max DD |
|---|---|---|---|---|---|
| Active | 0.92 | +0.10R | 1.19 | 22.8 | 13.5R |
| **Active + Selective** | **0.96** | **+0.12R** | **1.23** | **28.0** | **14.5R** |

Shënim: modeli H4 u ndërtua duke parë të gjithë periudhën, prandaj për të "periudha e panjohur"
nuk është plotësisht e panjohur. Për 49 modelet e tjera testi është i pastër.

## v1.03: dy mënyra, Active dhe Selective (`InpMode`)

Kërkesa ishte 4–5 trade në ditë. Testi me historikun real tregon se kjo metodë nuk i jep:
- Edhe me çdo qiri H4 dhe pa asnjë filtër, sinjalet dalin rreth 1.5–1.9 në ditë në M5 dhe 0.9–1.5 në M15.
- Pa filtrat ato humbin (−0.02R deri −0.05R për trade).
- Sa më shumë trade, aq më i dobët është çdo trade.

Mënyra më aktive që fiton ende është **Active** dhe është vlera fillestare:

| | Active (fillestare) | Selective |
|---|---|---|
| Qirinjtë H4 | 1AM, 5AM, 9AM, 1PM, gjithë qiriri | 1AM 2–4, 5AM 5–7, 9AM 9:30–11 |
| Hyrja | M15 | M30 |
| Rregulli OHLC | jo | po |
| Dalja | SL/TP ose pas 8 orësh | SL/TP ose në 12:00 NY |
| Trade në ditë | deri 5 (një njëherësh) | 1 |
| E përbashkët | trend 50 ditë, premium/discount, TP 1:2, mbyllje të premten në 16:00 NY | |

Rezultatet (simulim me historikun e FP Trading, 0.5% rrezik për trade):

| | Periudha | Trade | Në javë | Win | PF | Max DD | Fitimi |
|---|---|---|---|---|---|---|---|
| **Active** | 2022.07–2026.09 (M15) | 932 | ~4 | 44% | 1.23 | 13.4R | +72% |
| Active, rregullat në M30 | 2020.02–2026.09 | 842 | ~2.5 | 45% | 1.19 | 18.1R | çdo vit + |
| **Selective** | 2020.02–2026.09 (M30) | 74 | ~0.2 | 55% | 2.17 | 6.2R | +19.7% |

- **Active** është pozitiv çdo vit (2022 +5R, 2023 +34R, 2024 +21R, 2025 +43R, 2026 +8R).
  Avantazhi vjen nga **trendi ditor**: pa të, Active humb (−0.02R). Në një vit pa trend, prit rezultat afër zeros.
- Avantazhi për trade është i hollë (+0.12R), por mbetet pozitiv edhe me spread +0.30 $ (PF 1.12).
- Seria më e gjatë e humbjeve në Active është 11 trade radhazi (≈ −5.5% me 0.5% rrezik).

## v1.02: testi me historikun real të FP Trading (2020–2026)

Të dhënat: eksportet MT5 të llogarisë demo (M30/H1/H4/D1 nga 2020.02, M15 nga 2022.07,
M5 nga 2025.05). Ora e serverit u verifikua: java hapet të hënën 01:00, dita mbyllet 00:00,
pra **server = New York + 7**.

Çfarë tregoi testi:
- v1.01 (M15, bias CRT ditore/dita e kaluar) mbi M15 2022–2026: 113 trade, **PF 1.00**. Blerjet
  fitonin (+0.22R), shitjet humbnin (−0.30R): ari ishte në trend, jo avantazh i CRT-së.
- Hyrja **M30** jep sinjale më të pastra se M15, dhe **filtri i trendit ditor** (mesatarja 50-ditore)
  e përmirëson ndjeshëm. Filtri **OHLC** i PDF-së është filtri më i rëndësishëm (pa të: +0.15R, me të: +0.49R).

v1.02 (vlerat fillestare) mbi XAUUSD M30, 2020.02 – 2026.09, spread-i i brokerit:

| Periudha | Trade | Win | Mesatarja | PF | Max DD | Fitimi me 0.5% rrezik |
|---|---|---|---|---|---|---|
| 2020–2023 | 48 | 50% | +0.37R | 1.82 | 6.2R | +9.2% |
| 2024–2026 | 26 | 65% | +0.71R | 3.04 | 3.0R | +9.5% |
| **Gjithsej** | **74** | **55%** | **+0.49R** | **2.17** | **6.2R** | **+19.7%** |

Çdo vit 2020–2026 doli pozitiv. Variantet përreth (trend 20/100 ditë, RR 1.5/3, pa premium/discount,
vetëm 1AM, hyrje M15) dalin të gjitha pozitive në të dy periudhat, pra rezultati nuk varet nga një
vlerë e vetme. Me spread +0.50 $ më të gjerë, PF bie në 1.42.

**Kujdes:**
- Rreth 11 trade në vit. Është strategji e rrallë dhe fitimi është i vogël por i qëndrueshëm.
- Konfigurimi u zgjodh duke parë të gjithë periudhën 2020–2026. Prova e vërtetë është demo live.
- Rezultati i MT5 Tester mund të ndryshojë pak nga simulimi (modeli i spread-it dhe i tick-eve).

## v1.01: pse v1.00 nuk dha asnjë hyrje

v1.00 kishte njëkohësisht tre filtra shumë të ngushtë:
- tregtonte vetëm kur kishte CRT ditore aktive (rreth 60% e ditëve nuk kanë);
- premium/discount i matur me ditën e kaluar;
- qiriri që bënte engulf dhe njëkohësisht një high/low të ri nuk llogaritej si hyrje.

Në simulim me të dhëna që imitojnë orarin e arit (3.7 vjet), v1.00 jep rreth 22 trade,
pra afërsisht një në 2 muaj. v1.01 jep rreth 110 trade, pra afërsisht një në javë:
- bias: CRT ditore, dhe kur nuk ka, qiriri ditor i kaluar;
- premium/discount: mesi i range-it Asia;
- engulf-i me high/low të ri tani llogaritet.

Në fund të çdo testi, Journal shfaq dy rreshta (shembull nga simulimi):

```
CRT 1AM FUNNEL: CRT candles 975 | no data 1 | no bias 0 | high sweeps 686 | low sweeps 664 | OB breaks 1229 | trades 111
CRT 1AM REJECTED: key time 448 | against bias 408 | OHLC 232 | premium/discount 30
```

Këta tregojnë sa qirinj 1AM u panë, sa sweep dhe sa OB break pati, si dhe cili filtër bllokoi
sa sinjale. Nëse del "no data" i madh, mungon historia; nëse "key time" është i madh,
kontrollo `InpNYOffset`.

## Testimi

1. Kopjo `Experts/CRT_1AM_EA.mq5` te `MQL5/Experts/`, hape në MetaEditor, **F7**.
2. Strategy Tester:
   - Expert: `CRT_1AM_EA`, Symbol: XAUUSD, Timeframe: M15
   - Date: **2023.01.01 – 2026.09.26**, Forward: **No**
   - Modeling: **1 minute OHLC**
   - `InpMode`: **Combined** (fillestare), Active, Selective ose Custom
3. Te **Inputs**: klik i djathtë → **Reset**. Mos ndrysho asgjë në provën e parë.
4. Pas testit dërgo skedën **Backtest** dhe rreshtat `CRT 1AM FUNNEL`, `CRT 1AM REJECTED`
   dhe `CRT 1AM SUMMARY` nga **Journal**.

Pastaj mund të krahasohen variantet me optimizim (Custom max):
`InpBias` (5 vlera), `InpTrendDays` (20, 50, 100), `InpEntryTF` (M15, M30), `InpRR` (1.5, 2, 3).

## Simulatori offline

`backtest/crt_1am_backtest.py` përdor të njëjtat rregulla mbi eksportet MT5
(`python3 crt_1am_backtest.py --mt5 ../data/XAUUSD_M30.csv`).
Te random walk (pa spread) mesatarja është rreth 0R (5 867 trade, −0.005R ± 0.016),
pra simulatori nuk krijon fitim ose humbje fallco. Eksportet vendosen te `data/`
(Ctrl+U → Bars → XAUUSD → Request → Export). Dosja `data/` nuk ruhet në git.
